locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ---------------------------------------------------------------------------
# Generated application-user password - never hardcoded
# ---------------------------------------------------------------------------

resource "random_password" "db" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# ---------------------------------------------------------------------------
# Latest Amazon Linux 2023 AMI
# ---------------------------------------------------------------------------

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# ---------------------------------------------------------------------------
# IT staff access (REQ-NCA-P1-02 / 2.3: "only accessible by the web servers
# and IT staff"). Session Manager gives authorized IAM users a browser-based
# shell on the instance with no SSH key, no open inbound port, and no bastion
# host - access is controlled entirely through IAM, and every command is
# logged. Outbound HTTPS to the SSM endpoints already works via the existing
# NAT Gateway, so no security group changes are needed.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "ec2_ssm" {
  name = "${local.name_prefix}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "${local.name_prefix}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name
}

# ---------------------------------------------------------------------------
# Self-managed MySQL-compatible database (MariaDB) on EC2 - replaces RDS,
# which is blocked by an organization-level Service Control Policy in this
# sandbox. Same network placement and security group as the original RDS
# design: private data-tier subnet, only reachable from the app tier.
# ---------------------------------------------------------------------------

resource "aws_instance" "mysql" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = var.data_subnet_ids[0]
  vpc_security_group_ids = [var.db_security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm.name

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  # Installs and configures MariaDB (MySQL-compatible) on first boot.
  # Note: the password is embedded here because Terraform renders it at
  # apply time - it ends up in the instance's user_data (visible to anyone
  # with EC2 describe-instance-attribute permissions) and in Terraform
  # state, same trade-off as the credentials we already store in Secrets
  # Manager below. Acceptable for this case study; a production setup
  # would fetch the secret at boot via an IAM instance profile instead.
  user_data = <<-EOT
    #!/bin/bash
    set -e
    dnf update -y
    dnf install -y mariadb105-server
    systemctl enable --now mariadb

    mysql -e "CREATE DATABASE IF NOT EXISTS ${var.db_name};"
    mysql -e "CREATE USER IF NOT EXISTS '${var.db_username}'@'%' IDENTIFIED BY '${random_password.db.result}';"
    mysql -e "GRANT ALL PRIVILEGES ON ${var.db_name}.* TO '${var.db_username}'@'%';"
    mysql -e "FLUSH PRIVILEGES;"

    sed -i "s/^bind-address.*/bind-address = 0.0.0.0/" /etc/my.cnf.d/mariadb-server.cnf || true
    systemctl restart mariadb
  EOT

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mysql"
  })
}

# ---------------------------------------------------------------------------
# Store credentials in Secrets Manager - same as the RDS design, so the
# app tier looks credentials up the same way regardless of which backend
# actually runs the database.
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "db_credentials" {
  name = "${local.name_prefix}-db-credentials"

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id

  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    host     = aws_instance.mysql.private_ip
    port     = 3306
    dbname   = var.db_name
  })
}
