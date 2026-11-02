locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "random_password" "db" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Passwords of the two database users of the SOAR ban history (CS2, A4 record_ban).
# Only letters and digits, so they are safe inside the SQL in user_data.
resource "random_password" "soar_writer" {
  length  = 32
  special = false
}

resource "random_password" "soar_reader" {
  length  = 32
  special = false
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name = "name"
    # Standard Amazon Linux 2023 image only. The old pattern "al2023-ami-*"
    # also matched the "minimal" image, which has no SSM agent - that is why
    # Session Manager stopped working.
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

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

    # ---- SOAR ban history (CS2, action A4 record_ban) ----
    # Database soar with the tables bans and ban_targets, and two users:
    # soar_writer: the SOAR, only from the AWS app subnets, may only ADD rows
    # soar_reader: mgmt01 in NetLab, may only READ the history
    mysql <<'SQL'
    CREATE DATABASE IF NOT EXISTS soar;
    USE soar;

    -- One row per ban decision of the SOAR (also a failed one)
    CREATE TABLE IF NOT EXISTS bans (
      id         INT AUTO_INCREMENT PRIMARY KEY,
      banned_at  DATETIME     NOT NULL COMMENT 'UTC',
      expires_at DATETIME     NULL     COMMENT 'UTC, empty when nothing was banned',
      src_ip     VARCHAR(45)  NOT NULL,
      status     ENUM('BANNED','PARTIAL','FAILED') NOT NULL,
      alert_type VARCHAR(64)  NOT NULL,
      alert_host VARCHAR(64)  NOT NULL COMMENT 'the attacked workstation',
      event_id   CHAR(36)     NOT NULL COMMENT 'same id as the incident file in S3',
      detail     VARCHAR(255) NOT NULL COMMENT 'answer of the ban script',
      INDEX idx_src_ip (src_ip),
      INDEX idx_banned_at (banned_at)
    ) ENGINE=InnoDB;

    -- One row per workstation of a ban: banned or failed
    CREATE TABLE IF NOT EXISTS ban_targets (
      ban_id      INT         NOT NULL,
      workstation VARCHAR(64) NOT NULL,
      result      ENUM('banned','failed') NOT NULL,
      PRIMARY KEY (ban_id, workstation),
      FOREIGN KEY (ban_id) REFERENCES bans (id)
    ) ENGINE=InnoDB;

    -- The bans that are active right now, per workstation
    CREATE OR REPLACE VIEW active_bans AS
      SELECT b.id, b.src_ip, t.workstation, b.banned_at, b.expires_at
      FROM bans b JOIN ban_targets t ON t.ban_id = b.id
      WHERE t.result = 'banned' AND b.expires_at > UTC_TIMESTAMP();

    CREATE USER IF NOT EXISTS 'soar_writer'@'${var.soar_writer_host}' IDENTIFIED BY '${random_password.soar_writer.result}';
    GRANT INSERT ON soar.* TO 'soar_writer'@'${var.soar_writer_host}';

    CREATE USER IF NOT EXISTS 'soar_reader'@'${var.soar_reader_host}' IDENTIFIED BY '${random_password.soar_reader.result}';
    GRANT SELECT ON soar.* TO 'soar_reader'@'${var.soar_reader_host}';
    FLUSH PRIVILEGES;
    SQL

    sed -i "s/^bind-address.*/bind-address = 0.0.0.0/" /etc/my.cnf.d/mariadb-server.cnf || true
    systemctl restart mariadb

    useradd --no-create-home --shell /usr/sbin/nologin node_exporter || true
    curl -sL https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz -o /tmp/node_exporter.tar.gz
    tar xzf /tmp/node_exporter.tar.gz -C /tmp
    cp /tmp/node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/
    chown node_exporter:node_exporter /usr/local/bin/node_exporter

    cat <<'SERVICE' > /etc/systemd/system/node_exporter.service
    [Unit]
    Description=Node Exporter
    After=network.target

    [Service]
    User=node_exporter
    Group=node_exporter
    Type=simple
    ExecStart=/usr/local/bin/node_exporter

    [Install]
    WantedBy=multi-user.target
    SERVICE

    systemctl daemon-reload
    systemctl enable --now node_exporter
  EOT

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mysql"
  })

  # The AMI and the user_data script are only used when the instance is
  # first created (user_data only runs on the first boot). Changes to them
  # afterwards - a newer AMI from AWS, or different line endings in the
  # script - should not stop, restart or replace the database.
  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${local.name_prefix}-db-credentials"
  recovery_window_in_days = 0 # delete at once on destroy, so the next apply can reuse the name

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

# Passwords of the SOAR database users. soar_writer is read by ECS for the SOAR;
# soar_reader is for the IT staff, to read the ban history from mgmt01.
resource "aws_secretsmanager_secret" "soar_writer" {
  name                    = "${local.name_prefix}-soar-db-writer"
  description             = "Password of the database user soar_writer (the SOAR, action A4 record_ban)"
  recovery_window_in_days = 0 # delete at once on destroy, so the next apply can reuse the name

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "soar_writer" {
  secret_id     = aws_secretsmanager_secret.soar_writer.id
  secret_string = random_password.soar_writer.result
}

resource "aws_secretsmanager_secret" "soar_reader" {
  name                    = "${local.name_prefix}-soar-db-reader"
  description             = "Password of the database user soar_reader (IT staff, read the ban history from mgmt01)"
  recovery_window_in_days = 0

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "soar_reader" {
  secret_id     = aws_secretsmanager_secret.soar_reader.id
  secret_string = random_password.soar_reader.result
}
