output "grafana_url" {
  description = "Grafana dashboard URL"
  value       = "http://${var.alb_dns_name}:${var.grafana_port}"
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "grafana_admin_secret_arn" {
  description = "Secrets Manager ARN holding the Grafana admin username/password"
  value       = aws_secretsmanager_secret.grafana_admin.arn
}

output "monitoring_security_group_id" {
  value = aws_security_group.monitoring.id
}
