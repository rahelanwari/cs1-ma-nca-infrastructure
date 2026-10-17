variable "project_name" {
  type    = string
  default = "innovatech-cs1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "alert_email" {
  description = "Email address to receive CloudWatch alarm notifications via SNS"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "app_subnet_ids" {
  description = "Private app-tier subnet IDs - the monitoring task runs here, same as the web tier"
  type        = list(string)
}

variable "alb_security_group_id" {
  type = string
}

variable "alb_arn" {
  description = "ARN of the existing ALB - a new listener (Grafana) is added to it"
  type        = string
}

variable "alb_arn_suffix" {
  description = "ARN suffix of the ALB, required for CloudWatch alarm dimensions"
  type        = string
}

variable "alb_dns_name" {
  type = string
}

variable "nginx_target_group_arn_suffix" {
  description = "ARN suffix of the Nginx target group, for the UnHealthyHostCount alarm"
  type        = string
}

variable "ecs_cluster_name" {
  type = string
}

variable "ecs_service_name" {
  description = "Name of the Nginx ECS service - the same CPU metric that drives Auto Scaling is used for the high-CPU alarm"
  type        = string
}

variable "db_security_group_id" {
  description = "Security group of the database instance - a rule is added allowing Prometheus to scrape node_exporter on port 9100"
  type        = string
}

variable "db_private_ip" {
  description = "Private IP of the database EC2 instance, scraped by Prometheus via node_exporter"
  type        = string
}

variable "cpu_alarm_threshold" {
  description = "CPU % above which IT staff are alerted. Set higher than the 60% Auto Scaling target, so this only fires when scaling alone hasn't resolved the load."
  type        = number
  default     = 80
}

variable "grafana_port" {
  type    = number
  default = 3000
}

variable "task_cpu" {
  description = "Fargate CPU units for the Prometheus+Grafana task"
  type        = string
  default     = "512"
}

variable "task_memory" {
  description = "Fargate memory (MiB) for the Prometheus+Grafana task"
  type        = string
  default     = "1024"
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "loki_url" {
  description = "Loki on mgmt01 in NetLab, reached over the VPN by its private DNS name"
  type        = string
  default     = "http://loki.innovatech.internal:3100"
}

variable "vpn_connection_id" {
  description = "ID of the Site-to-Site VPN connection (used by alert rule R4)"
  type        = string
}

variable "vpn_tunnel1_address" {
  description = "Public IP of VPN tunnel 1 (dashboard panel tunnel state)"
  type        = string
}

variable "vpn_tunnel2_address" {
  description = "Public IP of VPN tunnel 2 (dashboard panel tunnel state)"
  type        = string
}

variable "soar_webhook_url" {
  description = "Webhook of the SOAR; Grafana sends every alert here (contact point)"
  type        = string
  default     = "http://soar.innovatech.internal:8080/alerts"
}

variable "soar_discovery_name" {
  description = "Service discovery name of the SOAR tasks; Prometheus scrapes every task"
  type        = string
  default     = "soar.svc.innovatech.internal"
}