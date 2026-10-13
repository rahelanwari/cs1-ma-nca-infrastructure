# Inputs for the VPN module

variable "project_name" {
  description = "Name used to prefix and tag all resources"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g. dev, prod)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC the VPN gateway is attached to"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC (AWS side of the tunnel)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_route_table_id" {
  description = "Route table of the private app and data subnets; gets the route to NetLab"
  type        = string
}

variable "db_security_group_id" {
  description = "Security group of the database server; allows SSH from the NetLab management segment"
  type        = string
}

variable "customer_gateway_ip" {
  description = "Public IP address that NetLab (fw01) uses on the internet"
  type        = string
}

variable "onprem_mgmt_cidr" {
  description = "NetLab management segment that may use the VPN (mgmt01)"
  type        = string
  default     = "192.168.20.0/24"
}