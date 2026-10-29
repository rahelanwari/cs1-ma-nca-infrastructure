"""Innovatech SOAR - event listener for Grafana alerts.

POST /alerts   Grafana contact point (webhook) sends the alerts here
GET  /metrics  Prometheus metrics for the SOAR row on the dashboard (P2-09)
GET  /health   simple health check
"""

import logging
import os
import time

from flask import Flask, jsonify, request
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    CollectorRegistry,
    Counter,
    Histogram,
    generate_latest,
)

from actions import Actions, SshBlocker
from engine import (
    KNOWN_ACTIONS,
    SOURCES,
    TIERS,
    actions_for,
    load_rules,
    normalize_alert,
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("soar")

DEFAULT_RULES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rules.yaml")


def actions_from_env():
    """Build the real actions from environment variables (used in ECS)."""
    if os.environ.get("DRY_RUN", "false").lower() == "true":
        return Actions(dry_run=True)

    import boto3  # only needed when the SOAR really talks to AWS

    bucket = os.environ["INCIDENT_BUCKET"]
    topic_arn = os.environ["SNS_TOPIC_ARN"]
    region = os.environ.get("AWS_REGION", "eu-west-1")

    # A3 block_ip: only when the connection to mgmt01 is configured
    blocker = None
    if os.environ.get("BLOCK_HOST"):
        blocker = SshBlocker(host=os.environ["BLOCK_HOST"],
                             user=os.environ.get("BLOCK_USER", "student"),
                             private_key=os.environ["BLOCK_SSH_KEY"],
                             host_key=os.environ["BLOCK_HOST_KEY"])

    return Actions(s3=boto3.client("s3", region_name=region),
                   sns=boto3.client("sns", region_name=region),
                   bucket=bucket, topic_arn=topic_arn, blocker=blocker)


def create_app(rules=None, actions=None, registry=None):
    app = Flask(__name__)
    rules = rules or load_rules(os.environ.get("SOAR_RULES_FILE", DEFAULT_RULES))
    actions = actions or actions_from_env()
    registry = registry or CollectorRegistry()

    events = Counter("soar_events_received_total", "Firing alerts received",
                     ["type", "severity", "source"], registry=registry)
    action_runs = Counter("soar_actions_total", "Response actions and their result",
                          ["action", "result"], registry=registry)
    skipped = Counter("soar_events_skipped_total", "Alerts not acted on",
                      ["reason"], registry=registry)
    invalid = Counter("soar_invalid_requests_total", "Requests that were not a valid Grafana alert",
                      registry=registry)
    duration = Histogram("soar_processing_seconds", "Time to process one alert", registry=registry)

    # Start all known series at 0. Prometheus then sees the counter go from 0 to 1,
    # so increase() in Grafana also counts the first alert of a type.
    for alert_type in rules["rules"]:
        for severity in TIERS:
            for source in SOURCES:
                events.labels(type=alert_type, severity=severity, source=source)
    for name in KNOWN_ACTIONS:
        for result in ("success", "failed"):
            action_runs.labels(action=name, result=result)
    skipped.labels(reason="resolved")

    def run(name, func, *args):
        """Run one action. A failing action is counted and logged; the other actions still run."""
        try:
            result = func(*args)
            action_runs.labels(action=name, result="success").inc()
            return {"action": name, "result": "success", "detail": result}
        except Exception as exc:  # noqa: BLE001 - any failure must be visible, never crash the SOAR
            action_runs.labels(action=name, result="failed").inc()
            log.error("action %s failed: %s", name, exc)
            return {"action": name, "result": "failed", "detail": str(exc)}

    def handle(alert):
        event = normalize_alert(alert)
        if event["status"] != "firing":
            skipped.labels(reason="resolved").inc()
            log.info("skipped resolved alert type=%s host=%s", event["type"], event["host"])
            return {"type": event["type"], "skipped": "resolved"}

        start = time.perf_counter()
        events.labels(type=event["type"], severity=event["severity"], source=event["source"]).inc()
        planned = actions_for(rules, event["type"])
        log.info("event type=%s tier=%s host=%s actions=%s",
                 event["type"], event["tier"], event["host"], planned)

        # Other actions first, so the incident record also contains their results
        results = [run(name, getattr(actions, name), event) for name in planned if name != "log_incident"]
        if "log_incident" in planned:
            results.append(run("log_incident", actions.log_incident, event, results))
        duration.observe(time.perf_counter() - start)
        return {"id": event["id"], "type": event["type"], "tier": event["tier"], "actions": results}

    @app.post("/alerts")
    def alerts():
        payload = request.get_json(silent=True)
        if not isinstance(payload, dict) or not isinstance(payload.get("alerts"), list):
            invalid.inc()
            return jsonify(error="expected a Grafana webhook with an 'alerts' list"), 400
        return jsonify(processed=[handle(a) for a in payload["alerts"]])

    @app.get("/metrics")
    def metrics():
        return generate_latest(registry), 200, {"Content-Type": CONTENT_TYPE_LATEST}

    @app.get("/health")
    def health():
        return jsonify(status="ok")

    return app