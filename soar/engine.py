"""Rule engine of the SOAR.

Turns a Grafana alert into one simple event (type, severity, source, host)
and decides which response actions must run, based on rules.yaml.
"""

import uuid
from datetime import UTC, datetime

import yaml

KNOWN_ACTIONS = {"log_incident", "notify", "block_ip"}

# Severity label of the alert -> response tier (Phase 1 design, 6.3)
TIERS = {"low": "LOW", "medium": "MEDIUM", "high": "CRITICAL"}

# Values of the "source" label of the alert rules (on-premises or AWS)
SOURCES = ("onprem", "cloud")


def load_rules(path):
    """Read rules.yaml and check it. Returns {"rules": {type: [actions]}, "default": [actions]}."""
    with open(path, encoding="utf-8") as f:
        data = yaml.safe_load(f)

    rules = {}
    for rule in data.get("rules", []):
        rules[rule["type"]] = list(rule["actions"])
    default = list(data.get("default", {}).get("actions", []))

    # A typo in rules.yaml must stop the SOAR (and the pipeline), not fail silently later
    for actions in list(rules.values()) + [default]:
        unknown = set(actions) - KNOWN_ACTIONS
        if unknown:
            raise ValueError(f"Unknown action(s) in rules file: {sorted(unknown)}")
    if not default:
        raise ValueError("The rules file needs a default rule with at least one action")

    return {"rules": rules, "default": default}


def actions_for(rules, event_type):
    """The actions for this event type, or the default actions for an unknown type."""
    return rules["rules"].get(event_type, rules["default"])


def tier_for(severity):
    """Response tier for a severity label. Unknown severity -> MEDIUM, so a person looks at it."""
    return TIERS.get(str(severity).lower(), "MEDIUM")


def normalize_alert(alert):
    """Turn one alert from the Grafana webhook into one SOAR event."""
    labels = alert.get("labels", {}) or {}
    annotations = alert.get("annotations", {}) or {}
    severity = labels.get("severity", "unknown")
    return {
        "id": str(uuid.uuid4()),
        "received_at": datetime.now(UTC).isoformat(timespec="seconds"),
        "status": alert.get("status", "firing"),
        "type": labels.get("type", "unknown"),
        "severity": severity,
        "tier": tier_for(severity),
        "source": labels.get("source", "unknown"),
        "host": labels.get("host", "unknown"),
        "src_ip": labels.get("src_ip", ""),
        "alertname": labels.get("alertname", ""),
        "summary": annotations.get("summary", ""),
        "starts_at": alert.get("startsAt", ""),
        "fingerprint": alert.get("fingerprint", ""),
        "alert": alert,  # the original alert, kept in the incident record
    }