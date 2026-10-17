# Outputs of the SOAR module

output "ecr_repository_url" {
  description = "ECR repository for the SOAR image (used by the SOAR pipeline)"
  value       = aws_ecr_repository.soar.repository_url
}

output "incident_bucket" {
  description = "S3 bucket with the incident records (action A1)"
  value       = aws_s3_bucket.incidents.bucket
}

output "service_name" {
  description = "ECS service of the SOAR"
  value       = aws_ecs_service.soar.name
}

output "soar_url" {
  description = "Webhook URL for the Grafana contact point"
  value       = "http://soar.${var.dns_zone_name}:${local.soar_port}/alerts"
}