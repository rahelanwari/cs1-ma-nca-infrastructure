output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "app_subnet_ids" {
  value = module.network.app_subnet_ids
}

output "data_subnet_ids" {
  value = module.network.data_subnet_ids
}

output "alb_security_group_id" {
  value = module.network.alb_security_group_id
}

output "app_security_group_id" {
  value = module.network.app_security_group_id
}

output "db_security_group_id" {
  value = module.network.db_security_group_id
}

output "alb_dns_name" {
  description = "Public URL to reach the deployed web app (http://<this value>)"
  value       = module.compute.alb_dns_name
}

output "ecs_cluster_name" {
  value = module.compute.ecs_cluster_name
}

output "ecs_service_name" {
  value = module.compute.ecs_service_name
}

output "ecr_repository_url" {
  value = module.compute.ecr_repository_url
}

output "db_endpoint" {
  description = "Database connection endpoint (host:port)"
  value       = module.database.db_endpoint
}

output "db_secret_arn" {
  description = "Secrets Manager ARN holding the DB credentials"
  value       = module.database.secret_arn
}

output "grafana_url" {
  description = "Grafana dashboard URL"
  value       = module.monitoring.grafana_url
}

output "grafana_admin_secret_arn" {
  description = "Secrets Manager ARN holding the Grafana admin username/password"
  value       = module.monitoring.grafana_admin_secret_arn
}

output "sns_topic_arn" {
  description = "SNS topic ARN that CloudWatch alarms notify"
  value       = module.monitoring.sns_topic_arn
}
