output "alb_dns_name" {
  description = "Public DNS name of the load balancer - use this to reach the web app"
  value       = aws_lb.main.dns_name
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.nginx.name
}

output "ecr_repository_url" {
  description = "URL of the ECR repository - push a custom Nginx image here"
  value       = aws_ecr_repository.nginx.repository_url
}

output "alb_arn" {
  value = aws_lb.main.arn
}

output "alb_arn_suffix" {
  value = aws_lb.main.arn_suffix
}

output "nginx_target_group_arn_suffix" {
  value = aws_lb_target_group.nginx.arn_suffix
}
