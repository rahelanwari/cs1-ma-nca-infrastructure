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

variable "data_subnet_ids" {
  description = "Private data-tier subnet IDs from the network module. The instance is placed in the first one - a single instance, not spread across AZs, since this is a self-managed replacement for RDS Multi-AZ."
  type        = list(string)
}

variable "db_security_group_id" {
  description = "Security group ID for the database, from the network module (only allows traffic from the app tier)"
  type        = string
}

variable "db_name" {
  description = "Database name created on first boot"
  type        = string
  default     = "innovatech"
}

variable "db_username" {
  description = "Application database user (not the OS user)"
  type        = string
  default     = "dbadmin"
}

variable "instance_type" {
  description = "EC2 instance type for the database server"
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB. Must be >= 30 for the Amazon Linux 2023 AMI's underlying snapshot."
  type        = number
  default     = 30
}

# ---------------------------------------------------------------- SOAR ban history (CS2)

variable "soar_writer_host" {
  description = "Where the SOAR may log in from as soar_writer: the AWS app subnets 10.0.10.0/23 (MariaDB netmask notation)"
  type        = string
  default     = "10.0.10.0/255.255.254.0"
}

variable "soar_reader_host" {
  description = "Where soar_reader may log in from: mgmt01 in NetLab (through the VPN)"
  type        = string
  default     = "192.168.20.10"
}
