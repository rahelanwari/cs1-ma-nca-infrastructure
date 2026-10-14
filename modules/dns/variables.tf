# Inputs for the DNS module

variable "project_name" {
  description = "Name used to prefix and tag all resources"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g. dev, prod)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC that can use the private zone"
  type        = string
}

variable "zone_name" {
  description = "Name of the private DNS zone"
  type        = string
  default     = "innovatech.internal"
}

variable "db_private_ip" {
  description = "Private IP address of the database server"
  type        = string
}

variable "loki_ip" {
  description = "IP address of mgmt01 in NetLab (Loki), reachable over the VPN"
  type        = string
  default     = "192.168.20.10"
}