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

variable "soar_ssh_private_key" {
  description = "Private SSH key of the SOAR for the ban script on mgmt01 (from the GitHub secret SOAR_SSH_KEY)"
  type        = string
  sensitive   = true
}

variable "mgmt01_host_key" {
  description = "Public ed25519 host key of mgmt01 (base64 part of /etc/ssh/ssh_host_ed25519_key.pub)"
  type        = string
  default     = "AAAAC3NzaC1lZDI1NTE5AAAAIEe0V78QXUdEoEKPWxaYJNHQQLQ1jXZHOhMOBQ6f3lON"
}