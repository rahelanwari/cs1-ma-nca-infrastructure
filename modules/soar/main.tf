# =====================================================================
# SOAR module (CS2 block 6): Python SOAR service on ECS Fargate
# Grafana sends alerts to POST /alerts on port 8080; the SOAR stores
# incidents in S3 (A1), sends e-mails via SNS (A2) and bans the attacker
# on ws01 for 5 minutes via mgmt01 (A3, over the VPN).
# =====================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  soar_port = 8080
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------- image registry
resource "aws_ecr_repository" "soar" {
  name                 = "${local.name_prefix}-soar"
  image_tag_mutability = "MUTABLE"
  force_delete         = true # destroy also works when the repository still has images

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.common_tags
}

# ---------------------------------------------------------------- incident storage (A1)
resource "aws_s3_bucket" "incidents" {
  bucket        = "${local.name_prefix}-soar-incidents-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # destroy also works when the bucket still has incident files

  tags = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "incidents" {
  bucket                  = aws_s3_bucket.incidents.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "incidents" {
  bucket = aws_s3_bucket.incidents.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ---------------------------------------------------------------- network access
resource "aws_security_group" "soar" {
  name        = "${local.name_prefix}-soar-sg"
  description = "SOAR tasks - port 8080 only from the Grafana/Prometheus task"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Grafana webhook and Prometheus scrape"
    from_port       = local.soar_port
    to_port         = local.soar_port
    protocol        = "tcp"
    security_groups = [var.monitoring_security_group_id]
  }

  egress {
    description = "S3, SNS, ECR over HTTPS (NAT) and SSH to mgmt01 (VPN, ban script)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-soar-sg"
  })
}

# ---------------------------------------------------------------- permissions
data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Execution role: ECS may pull the image and write the container logs
resource "aws_iam_role" "execution" {
  name               = "${local.name_prefix}-soar-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ---------------------------------------------------------------- SSH key for A3 block_ip
# The private key comes from the GitHub secret SOAR_SSH_KEY, never from the code.
# On mgmt01 this key may ONLY run the ban script (forced command).
resource "aws_secretsmanager_secret" "block_key" {
  name                    = "${local.name_prefix}-soar-block-key"
  description             = "SSH key of the SOAR: may only run the ban script on mgmt01"
  recovery_window_in_days = 0 # delete at once on destroy, so the next apply can reuse the name
  tags                    = local.common_tags
}

resource "aws_secretsmanager_secret_version" "block_key" {
  secret_id     = aws_secretsmanager_secret.block_key.id
  secret_string = var.block_ssh_private_key
}

# The execution role may read this one secret, so ECS can give it to the container
resource "aws_iam_role_policy" "execution_block_key" {
  name = "${local.name_prefix}-soar-read-block-key"
  role = aws_iam_role.execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadBlockKey"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.block_key.arn
      }
    ]
  })
}

# Task role: the SOAR itself may ONLY write incidents and publish to the topic
resource "aws_iam_role" "task" {
  name               = "${local.name_prefix}-soar-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "task" {
  name = "${local.name_prefix}-soar-actions"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "LogIncident"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.incidents.arn}/incidents/*"
      },
      {
        Sid      = "Notify"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = var.sns_topic_arn
      }
    ]
  })
}

# ---------------------------------------------------------------- service discovery
# Cloud Map keeps the A records of the running SOAR tasks up to date.
# The record soar.innovatech.internal (below) points to this name.
resource "aws_service_discovery_private_dns_namespace" "svc" {
  name        = "svc.${var.dns_zone_name}"
  description = "Service discovery for ECS services (SOAR)"
  vpc         = var.vpc_id
  tags        = local.common_tags
}

resource "aws_service_discovery_service" "soar" {
  name = "soar"

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.svc.id
    routing_policy = "MULTIVALUE"

    dns_records {
      type = "A"
      ttl  = 10
    }
  }

  tags = local.common_tags
}

resource "aws_route53_record" "soar" {
  zone_id = var.dns_zone_id
  name    = "soar.${var.dns_zone_name}"
  type    = "CNAME"
  ttl     = 60
  records = ["soar.svc.${var.dns_zone_name}"]
}

# ---------------------------------------------------------------- the SOAR service
resource "aws_cloudwatch_log_group" "soar" {
  name              = "/ecs/${local.name_prefix}-soar"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

resource "aws_ecs_task_definition" "soar" {
  family                   = "${local.name_prefix}-soar"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name         = "soar"
      image        = "${aws_ecr_repository.soar.repository_url}:latest"
      essential    = true
      portMappings = [{ containerPort = local.soar_port, protocol = "tcp" }]

      environment = [
        { name = "INCIDENT_BUCKET", value = aws_s3_bucket.incidents.bucket },
        { name = "SNS_TOPIC_ARN", value = var.sns_topic_arn },
        { name = "AWS_REGION", value = data.aws_region.current.name },
        { name = "BLOCK_HOST", value = var.block_host },
        { name = "BLOCK_USER", value = "student" },
        { name = "BLOCK_HOST_KEY", value = var.block_host_key }
      ]

      # A3 block_ip: ECS reads the private key from Secrets Manager at start-up
      secrets = [
        { name = "BLOCK_SSH_KEY", valueFrom = aws_secretsmanager_secret.block_key.arn }
      ]

      # ECS replaces a task that stops answering on /health
      healthCheck = {
        command     = ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:${local.soar_port}/health')\" || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 15
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.soar.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "soar"
        }
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_service" "soar" {
  name            = "${local.name_prefix}-soar-service"
  cluster         = var.ecs_cluster_name
  task_definition = aws_ecs_task_definition.soar.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.app_subnet_ids
    security_groups  = [aws_security_group.soar.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.soar.arn
  }

  depends_on = [
    aws_iam_role_policy_attachment.execution,
    aws_iam_role_policy.execution_block_key,
    aws_secretsmanager_secret_version.block_key
  ]

  tags = local.common_tags
}