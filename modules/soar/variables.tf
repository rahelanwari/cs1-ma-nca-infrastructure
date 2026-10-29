# Variables of the SOAR module (CS2 block 6)

variable "project_name" {
  description = "Name used to prefix and tag all resources"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g. dev)"
  type        = string
}

variable "vpc_id" {
  description = "VPC where the SOAR runs"
  type        = string
}

variable "app_subnet_ids" {
  description = "Private app subnets (two AZs) for the SOAR tasks"
  type        = list(string)
}

variable "ecs_cluster_name" {
  description = "Existing ECS cluster (Case Study 1)"
  type        = string
}

variable "monitoring_security_group_id" {
  description = "Security group of the Grafana/Prometheus task; only it may reach the SOAR"
  type        = string
}

variable "sns_topic_arn" {
  description = "SNS topic that sends the e-mails (action A2 notify)"
  type        = string
}

variable "dns_zone_id" {
  description = "Private hosted zone innovatech.internal (block 4)"
  type        = string
}

variable "dns_zone_name" {
  description = "Name of the private hosted zone"
  type        = string
  default     = "innovatech.internal"
}

variable "desired_count" {
  description = "Number of SOAR tasks (one per AZ)"
  type        = number
  default     = 2
}

variable "task_cpu" {
  description = "Fargate CPU units per SOAR task"
  type        = string
  default     = "256"
}

variable "task_memory" {
  description = "Fargate memory (MiB) per SOAR task"
  type        = string
  default     = "512"
}

variable "log_retention_days" {
  description = "How long the SOAR container logs are kept"
  type        = number
  default     = 14
}

# ---------------------------------------------------------------- action A3 block_ip

variable "block_ssh_private_key" {
  description = "Private SSH key of the SOAR for the ban script on mgmt01 (GitHub secret SOAR_SSH_KEY)"
  type        = string
  sensitive   = true
}

variable "block_host" {
  description = "mgmt01 in NetLab: runs the ban script for action A3 block_ip (over the VPN)"
  type        = string
  default     = "192.168.20.10"
}

variable "block_host_key" {
  description = "Public ed25519 host key of mgmt01 (base64 part), so the SOAR only trusts the real mgmt01"
  type        = string
}