# SOAR (Case Study 2)

Python SOAR service (filled in Phase 2):
- listener: receives Grafana alerts (POST /alerts)
- rule engine: rules.yaml (type + severity -> actions)
- actions: log incident (S3), notify (SNS e-mail), block IP (on all workstations, via mgmt01)
  and record ban (ban history in MariaDB)
- metrics: GET /metrics for Prometheus
- tests: pytest