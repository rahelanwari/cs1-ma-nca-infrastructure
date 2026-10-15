variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-1"
}

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

variable "netlab_public_ip" {
  description = "Public IP address that Fontys NetLab (fw01) uses on the internet"
  type        = string
  default     = "145.220.75.5"
}

variable "vpn_tunnel1_psk" {
  description = "Pre-shared key of VPN tunnel 1 (from the GitHub secret VPN_TUNNEL1_PSK)"
  type        = string
  sensitive   = true
}

variable "vpn_tunnel2_psk" {
  description = "Pre-shared key of VPN tunnel 2 (from the GitHub secret VPN_TUNNEL2_PSK)"
  type        = string
  sensitive   = true
}