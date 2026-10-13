# =====================================================================
# SITE-TO-SITE VPN (Case Study 2)
# ---------------------------------------------------------------------
# Connects the NetLab management segment (192.168.20.0/24, behind the
# pfSense firewall fw01) to the VPC (10.0.0.0/16) with an IPsec VPN.
# AWS always creates two tunnels; fw01 starts the connection, because
# it is behind the NAT of NetLab.
# =====================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# AWS side of the VPN: a virtual private gateway attached to the VPC
resource "aws_vpn_gateway" "main" {
  vpc_id = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vgw"
  })
}

# On-prem side of the VPN: the public IP that NetLab uses for fw01
resource "aws_customer_gateway" "netlab" {
  bgp_asn    = 65000
  ip_address = var.customer_gateway_ip
  type       = "ipsec.1"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cgw-netlab"
  })
}

# The VPN connection with two tunnels. Static routing (no BGP) and fixed
# IKEv2 settings, so the pfSense side can use exactly the same values.
resource "aws_vpn_connection" "netlab" {
  vpn_gateway_id      = aws_vpn_gateway.main.id
  customer_gateway_id = aws_customer_gateway.netlab.id
  type                = "ipsec.1"
  static_routes_only  = true

  # Traffic that may use the tunnel: NetLab MGMT <-> VPC
  local_ipv4_network_cidr  = var.onprem_mgmt_cidr
  remote_ipv4_network_cidr = var.vpc_cidr

  tunnel1_ike_versions                 = ["ikev2"]
  tunnel1_phase1_encryption_algorithms = ["AES256"]
  tunnel1_phase1_integrity_algorithms  = ["SHA2-256"]
  tunnel1_phase1_dh_group_numbers      = [14]
  tunnel1_phase2_encryption_algorithms = ["AES256"]
  tunnel1_phase2_integrity_algorithms  = ["SHA2-256"]
  tunnel1_phase2_dh_group_numbers      = [14]

  tunnel2_ike_versions                 = ["ikev2"]
  tunnel2_phase1_encryption_algorithms = ["AES256"]
  tunnel2_phase1_integrity_algorithms  = ["SHA2-256"]
  tunnel2_phase1_dh_group_numbers      = [14]
  tunnel2_phase2_encryption_algorithms = ["AES256"]
  tunnel2_phase2_integrity_algorithms  = ["SHA2-256"]
  tunnel2_phase2_dh_group_numbers      = [14]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpn-netlab"
  })
}

# Static route: traffic for the NetLab MGMT segment goes into the VPN
resource "aws_vpn_connection_route" "netlab_mgmt" {
  vpn_connection_id      = aws_vpn_connection.netlab.id
  destination_cidr_block = var.onprem_mgmt_cidr
}

# Put that route in the private route table (app and data subnets).
# The public route table does not get it: the ALB never talks to NetLab.
resource "aws_vpn_gateway_route_propagation" "private" {
  vpn_gateway_id = aws_vpn_gateway.main.id
  route_table_id = var.private_route_table_id
}

# mgmt01 (Ansible) may reach the database server over SSH, only through
# the VPN and only from the NetLab management segment.
resource "aws_security_group_rule" "db_ssh_from_netlab" {
  type              = "ingress"
  description       = "SSH from NetLab MGMT (Ansible updates) via VPN"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.onprem_mgmt_cidr]
  security_group_id = var.db_security_group_id
}