# =====================================================================
# PRIVATE DNS (Case Study 2, REQ-NCA-P2-04)
# ---------------------------------------------------------------------
# A Route 53 private hosted zone "innovatech.internal". Only resources
# inside the VPC can resolve these names; they always point to private
# IP addresses. Services use a name instead of an IP address, so a new
# IP only has to be changed here.
# =====================================================================

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# The private zone, connected to the VPC
resource "aws_route53_zone" "internal" {
  name    = var.zone_name
  comment = "Private DNS for Innovatech (CS2)"

  vpc {
    vpc_id = var.vpc_id
  }

  tags = local.common_tags
}

# db.innovatech.internal -> database server (private data subnet)
resource "aws_route53_record" "db" {
  zone_id = aws_route53_zone.internal.zone_id
  name    = "db.${var.zone_name}"
  type    = "A"
  ttl     = 300
  records = [var.db_private_ip]
}

# loki.innovatech.internal -> mgmt01 in NetLab (log storage, via the VPN)
resource "aws_route53_record" "loki" {
  zone_id = aws_route53_zone.internal.zone_id
  name    = "loki.${var.zone_name}"
  type    = "A"
  ttl     = 300
  records = [var.loki_ip]
}