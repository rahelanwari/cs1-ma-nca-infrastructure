variable "project_name" {
  description = "Name used to prefix and tag all resources"
  type        = string
  default     = "innovatech-cs1"
}

variable "environment" {
  description = "Environment name (e.g. dev, prod)"
  type        = string
  default     = "dev"
}

variable "vpc_id" {
  description = "VPC ID from the network module"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs (for the ALB) from the network module"
  type        = list(string)
}

variable "app_subnet_ids" {
  description = "Private app-tier subnet IDs (for ECS tasks) from the network module"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group ID for the ALB, from the network module"
  type        = string
}

variable "app_security_group_id" {
  description = "Security group ID for the app tier, from the network module"
  type        = string
}

variable "container_port" {
  description = "Port the Nginx container listens on"
  type        = number
  default     = 80
}

variable "container_image" {
  description = "Container image to run. Defaults to the public Nginx image so the service can be deployed immediately; switch to your ECR image URI once you've pushed a custom build."
  type        = string
  default     = "nginx:latest"
}

variable "task_cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU, matching the Week 1 TCO baseline assumption)"
  type        = string
  default     = "256"
}

variable "task_memory" {
  description = "Fargate task memory in MiB (matching the Week 1 TCO baseline assumption of 1 vCPU/1GB per task... adjusted to 512MB for the 256 CPU tier)"
  type        = string
  default     = "512"
}

variable "desired_count" {
  description = "Baseline (off-peak) number of running tasks"
  type        = number
  default     = 2
}

variable "min_capacity" {
  description = "Minimum number of tasks Auto Scaling will scale down to (off-peak)"
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum number of tasks Auto Scaling will scale up to (peak, e.g. ticket sales)"
  type        = number
  default     = 10
}

variable "cpu_target_value" {
  description = "Target average CPU utilization (%) that triggers scale out/in"
  type        = number
  default     = 60
}

variable "log_retention_days" {
  description = "CloudWatch log retention for container logs"
  type        = number
  default     = 14
}
