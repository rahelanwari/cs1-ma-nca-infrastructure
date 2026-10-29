"""Tests for the SOAR: rule engine, actions and the HTTP endpoints.

AWS is replaced by fake clients, so the tests never send e-mails or write to S3.
"""

import copy
import json
import os

import pytest
from prometheus_client import CollectorRegistry

from actions import Actions
from app import DEFAULT_RULES, create_app
from engine import actions_for, load_rules, normalize_alert, tier_for

HERE = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(HERE, "sample_alert.json"), encoding="utf-8") as f:
    SAMPLE = json.load(f)


class FakeS3:
    def __init__(self, fail=False):
        self.objects = []
        self.fail = fail

    def put_object(self, **kwargs):
        if self.fail:
            raise RuntimeError("S3 is not reachable")
        self.objects.append(kwargs)


class FakeSNS:
    def __init__(self):
        self.messages = []

    def publish(self, **kwargs):
        self.messages.append(kwargs)


class FakeBlocker:
    """Stands in for the SSH connection to mgmt01 (action A3 block_ip)."""

    def __init__(self, fail=False):
        self.banned = []
        self.fail = fail

    def ban(self, ip):
        if self.fail:
            raise RuntimeError("mgmt01 is not reachable")
        self.banned.append(ip)
        return f"BANNED: {ip} on ws01 for 5 minutes"


def make_client(s3_fails=False, blocker=None):
    """A test client of the SOAR with fake AWS clients and its own metrics."""
    s3, sns = FakeS3(fail=s3_fails), FakeSNS()
    actions = Actions(s3=s3, sns=sns, bucket="test-bucket", topic_arn="arn:aws:sns:eu-west-1:123:test",
                      blocker=blocker or FakeBlocker())
    app = create_app(rules=load_rules(DEFAULT_RULES), actions=actions, registry=CollectorRegistry())
    return app.test_client(), s3, sns


def webhook(alert_type, severity, host="ws01", src_ip="", status="firing"):
    """A Grafana webhook with one alert, based on the real sample."""
    payload = copy.deepcopy(SAMPLE)
    labels = payload["alerts"][0]["labels"]
    labels.update(type=alert_type, severity=severity, host=host, src_ip=src_ip)
    payload["alerts"][0]["status"] = status
    return payload


# ---------------------------------------------------------------- rule engine

def test_rules_file_is_valid_and_covers_all_alert_rules():
    rules = load_rules(DEFAULT_RULES)
    for alert_type in ["ssh_failed_login", "ssh_brute_force", "port_scan", "vpn_down", "log_source_silent"]:
        assert alert_type in rules["rules"]
    assert rules["default"] == ["log_incident", "notify"]


def test_unknown_action_in_rules_file_is_rejected(tmp_path):
    bad = tmp_path / "rules.yaml"
    bad.write_text("rules:\n  - type: x\n    actions: [send_sms]\ndefault:\n  actions: [notify]\n")
    with pytest.raises(ValueError):
        load_rules(str(bad))


def test_tiers_follow_the_severity():
    assert tier_for("low") == "LOW"
    assert tier_for("medium") == "MEDIUM"
    assert tier_for("high") == "CRITICAL"
    assert tier_for("something-else") == "MEDIUM"


def test_unknown_type_gets_the_default_rule():
    rules = load_rules(DEFAULT_RULES)
    assert actions_for(rules, "brand_new_alert") == ["log_incident", "notify"]


def test_grafana_alert_is_normalized():
    event = normalize_alert(SAMPLE["alerts"][0])
    assert event["type"] == "ssh_brute_force"
    assert event["severity"] == "medium"
    assert event["tier"] == "MEDIUM"
    assert event["source"] == "onprem"
    assert event["host"] == "ws01"
    assert event["src_ip"] == "192.168.20.10"


# ---------------------------------------------------------------- response tiers

def test_low_tier_only_records_the_incident():
    client, s3, sns = make_client()
    response = client.post("/alerts", json=webhook("ssh_failed_login", "low"))
    assert response.status_code == 200
    assert len(s3.objects) == 1
    assert sns.messages == []


def test_medium_tier_records_and_notifies():
    client, s3, sns = make_client()
    client.post("/alerts", json=SAMPLE)
    assert len(s3.objects) == 1
    assert len(sns.messages) == 1
    assert sns.messages[0]["Subject"] == "[MEDIUM] ssh_brute_force on ws01 from 192.168.20.10"

    record = json.loads(s3.objects[0]["Body"])
    assert record["type"] == "ssh_brute_force"
    assert {"action": "notify", "result": "success",
            "detail": sns.messages[0]["Subject"]} in record["actions"]
    assert record["alert"]["labels"]["alertname"] == "R2 SSH brute force"


def test_high_tier_subject_is_critical():
    client, _, sns = make_client()
    client.post("/alerts", json=webhook("port_scan", "high", host="fw01", src_ip="192.168.10.10"))
    assert sns.messages[0]["Subject"].startswith("[CRITICAL] port_scan on fw01")


def test_resolved_alert_is_skipped():
    client, s3, sns = make_client()
    client.post("/alerts", json=webhook("ssh_brute_force", "medium", status="resolved"))
    assert s3.objects == []
    assert sns.messages == []


# ---------------------------------------------------------------- errors and monitoring

def test_failed_action_is_counted_and_other_actions_still_run():
    client, _, sns = make_client(s3_fails=True)
    response = client.post("/alerts", json=SAMPLE)
    assert response.status_code == 200
    assert len(sns.messages) == 1  # notify still ran

    metrics = client.get("/metrics").get_data(as_text=True)
    assert 'soar_actions_total{action="log_incident",result="failed"} 1.0' in metrics
    assert 'soar_actions_total{action="notify",result="success"} 1.0' in metrics


def test_invalid_request_returns_400():
    client, _, _ = make_client()
    response = client.post("/alerts", json={"hello": "world"})
    assert response.status_code == 400
    assert "soar_invalid_requests_total 1.0" in client.get("/metrics").get_data(as_text=True)


def has_sample(metrics, name, value, **labels):
    """True when /metrics contains this sample. The order of the labels does not matter."""
    return any(
        line.startswith(name + "{")
        and line.endswith(f"}} {value}")
        and all(f'{key}="{val}"' in line for key, val in labels.items())
        for line in metrics.splitlines()
    )


def test_metrics_show_the_received_events():
    client, _, _ = make_client()
    client.post("/alerts", json=SAMPLE)
    metrics = client.get("/metrics").get_data(as_text=True)
    assert has_sample(metrics, "soar_events_received_total", "1.0",
                      type="ssh_brute_force", severity="medium", source="onprem")
    assert "soar_processing_seconds_count 1.0" in metrics


def test_metrics_start_at_zero():
    client, _, _ = make_client()
    metrics = client.get("/metrics").get_data(as_text=True)
    assert has_sample(metrics, "soar_events_received_total", "0.0",
                      type="port_scan", severity="high", source="onprem")
    assert has_sample(metrics, "soar_actions_total", "0.0", action="notify", result="failed")


def test_health():
    client, _, _ = make_client()
    assert client.get("/health").get_json() == {"status": "ok"}


# ---------------------------------------------------------------- block action (A3)

def test_brute_force_blocks_the_attacker():
    blocker = FakeBlocker()
    client, s3, sns = make_client(blocker=blocker)
    client.post("/alerts", json=webhook("ssh_brute_force", "medium", src_ip="192.168.10.66"))
    assert blocker.banned == ["192.168.10.66"]
    assert len(sns.messages) == 1

    record = json.loads(s3.objects[0]["Body"])
    assert record["actions"][0] == {"action": "block_ip", "result": "success",
                                    "detail": "BANNED: 192.168.10.66 on ws01 for 5 minutes"}


def test_whitelisted_ip_is_never_blocked():
    blocker = FakeBlocker()
    client, _, sns = make_client(blocker=blocker)
    client.post("/alerts", json=SAMPLE)  # src_ip 192.168.20.10 is mgmt01
    assert blocker.banned == []
    assert len(sns.messages) == 1  # the e-mail is still sent

    metrics = client.get("/metrics").get_data(as_text=True)
    assert has_sample(metrics, "soar_actions_total", "1.0", action="block_ip", result="failed")


@pytest.mark.parametrize("bad_ip", ["", "1.2.3.4; reboot", "999.1.1.1", "ws01"])
def test_block_ip_only_accepts_one_ip_address(bad_ip):
    blocker = FakeBlocker()
    event = normalize_alert(webhook("ssh_brute_force", "medium", src_ip=bad_ip)["alerts"][0])
    with pytest.raises(ValueError):
        Actions(blocker=blocker).block_ip(event)
    assert blocker.banned == []


def test_failed_block_still_sends_the_email():
    client, s3, sns = make_client(blocker=FakeBlocker(fail=True))
    client.post("/alerts", json=webhook("ssh_brute_force", "medium", src_ip="192.168.10.66"))
    assert len(sns.messages) == 1
    record = json.loads(s3.objects[0]["Body"])
    assert record["actions"][0]["action"] == "block_ip"
    assert record["actions"][0]["result"] == "failed"