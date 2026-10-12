# SOAR (Case Study 2)

Python SOAR service (filled in Phase 2):
- listener: receives Grafana alerts (POST /alerts)
- rule engine: rules.yaml (type + severity -> actions)
- actions: log incident (S3) and notify (SNS e-mail)
- metrics: GET /metrics for Prometheus
- tests: pytest