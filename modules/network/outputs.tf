output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (ALB, NAT Gateway)"
  value       = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  description = "IDs of the private app-tier subnets (ECS Fargate)"
  value       = aws_subnet.app[*].id
}

output "data_subnet_ids" {
  description = "IDs of the private data-tier subnets (RDS)"
  value       = aws_subnet.data[*].id
}

output "alb_security_group_id" {
  description = "Security group ID for the ALB"
  value       = aws_security_group.alb.id
}

output "app_security_group_id" {
  description = "Security group ID for the app tier (ECS tasks)"
  value       = aws_security_group.app.id
}

output "db_security_group_id" {
  description = "Security group ID for the data tier (RDS)"
  value       = aws_security_group.db.id
}
