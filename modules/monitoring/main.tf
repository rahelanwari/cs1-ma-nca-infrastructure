locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

data "aws_region" "current" {}

# -------------------------------------------------------------------
# Grafana provisioning (data sources + dashboard as code).
# Grafana reads these files at every start, so a new monitoring task
# always comes up with the same data sources and the same dashboard.
# -------------------------------------------------------------------
locals {
  # Data sources with a FIXED uid, so the dashboard JSON can refer to them
  grafana_datasources = <<-YAML
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        uid: prometheus
        access: proxy
        url: http://localhost:9090
        isDefault: true
      - name: CloudWatch
        type: cloudwatch
        uid: cloudwatch
        jsonData:
          authType: default
          defaultRegion: ${data.aws_region.current.name}
  YAML

  # Tells Grafana to load every dashboard JSON file from this folder
  grafana_dashboard_provider = <<-YAML
    apiVersion: 1
    providers:
      - name: innovatech
        type: file
        disableDeletion: true
        options:
          path: /etc/grafana/provisioning/dashboards
  YAML

  # The dashboard itself, with the real ALB / target group / ECS names filled in
  grafana_dashboard_json = templatefile("${path.module}/dashboards/innovatech.json.tftpl", {
    alb_arn_suffix          = var.alb_arn_suffix
    target_group_arn_suffix = var.nginx_target_group_arn_suffix
    ecs_cluster_name        = var.ecs_cluster_name
    ecs_service_name        = var.ecs_service_name
  })
}

resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts"
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${local.name_prefix}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  alarm_description   = "Nginx service average CPU has stayed above ${var.cpu_alarm_threshold}% for 2 minutes, even with Auto Scaling active."
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
  tags          = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "service_failure" {
  alarm_name          = "${local.name_prefix}-unhealthy-targets"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "One or more Nginx tasks are failing the ALB health check - possible service failure."
  treat_missing_data  = "notBreaching"

  dimensions = {
    TargetGroup  = var.nginx_target_group_arn_suffix
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
  tags          = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "connectivity" {
  alarm_name          = "${local.name_prefix}-elb-5xx"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "The load balancer is returning 5XX errors - a connectivity issue reaching the backend."
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = local.common_tags
}

resource "aws_security_group" "monitoring" {
  name        = "${local.name_prefix}-monitoring-sg"
  description = "Prometheus + Grafana task - Grafana reachable only via the ALB"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Grafana from ALB"
    from_port       = var.grafana_port
    to_port         = var.grafana_port
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-monitoring-sg"
  })
}

resource "aws_security_group_rule" "db_allow_monitoring_scrape" {
  type                     = "ingress"
  from_port                = 9100
  to_port                  = 9100
  protocol                 = "tcp"
  security_group_id        = var.db_security_group_id
  source_security_group_id = aws_security_group.monitoring.id
  description              = "node_exporter scrape from Prometheus"
}

resource "aws_security_group_rule" "alb_allow_grafana" {
  type              = "ingress"
  from_port         = var.grafana_port
  to_port           = var.grafana_port
  protocol          = "tcp"
  security_group_id = var.alb_security_group_id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Grafana dashboard access"
}

resource "random_password" "grafana_admin" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+"
}

resource "aws_secretsmanager_secret" "grafana_admin" {
  name = "${local.name_prefix}-grafana-admin"
  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "grafana_admin" {
  secret_id = aws_secretsmanager_secret.grafana_admin.id
  secret_string = jsonencode({
    username = "admin"
    password = random_password.grafana_admin.result
  })
}

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

resource "aws_iam_role" "execution" {
  name               = "${local.name_prefix}-monitoring-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  name               = "${local.name_prefix}-monitoring-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "grafana_cloudwatch" {
  name = "${local.name_prefix}-grafana-cloudwatch-read"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "cloudwatch:DescribeAlarmsForMetric",
        "cloudwatch:DescribeAlarmHistory",
        "cloudwatch:DescribeAlarms",
        "cloudwatch:ListMetrics",
        "cloudwatch:GetMetricData",
        "cloudwatch:GetMetricStatistics",
        "logs:DescribeLogGroups",
        "logs:GetLogGroupFields",
        "logs:StartQuery",
        "logs:StopQuery",
        "logs:GetQueryResults",
        "logs:GetLogEvents",
        "ec2:DescribeTags",
        "ec2:DescribeInstances",
        "ec2:DescribeRegions",
        "tag:GetResources"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_cloudwatch_log_group" "monitoring" {
  name              = "/ecs/${local.name_prefix}-monitoring"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

resource "aws_ecs_task_definition" "monitoring" {
  family                   = "${local.name_prefix}-monitoring"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name       = "prometheus"
      image      = "prom/prometheus:latest"
      essential  = true
      entryPoint = ["sh", "-c"]
      command = [
        <<-EOT
        cat <<'PCFG' > /etc/prometheus/prometheus.yml
        global:
          scrape_interval: 15s
        scrape_configs:
          - job_name: 'prometheus'
            static_configs:
              - targets: ['localhost:9090']
          - job_name: 'database'
            static_configs:
              - targets: ['${var.db_private_ip}:9100']
        PCFG
        exec /bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/prometheus
        EOT
      ]
      portMappings = [{ containerPort = 9090, protocol = "tcp" }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.monitoring.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "prometheus"
        }
      }
    },
    {
      name         = "grafana"
      image        = "grafana/grafana:latest"
      essential    = true
      portMappings = [{ containerPort = var.grafana_port, protocol = "tcp" }]
      entryPoint   = ["sh", "-c"]
      command = [
        <<-EOT
        # Write the provisioning files first, then start Grafana as normal (/run.sh)
        mkdir -p /etc/grafana/provisioning/datasources /etc/grafana/provisioning/dashboards
        echo '${base64encode(local.grafana_datasources)}' | base64 -d > /etc/grafana/provisioning/datasources/datasources.yaml
        echo '${base64encode(local.grafana_dashboard_provider)}' | base64 -d > /etc/grafana/provisioning/dashboards/provider.yaml
        echo '${base64encode(local.grafana_dashboard_json)}' | base64 -d > /etc/grafana/provisioning/dashboards/innovatech.json
        exec /run.sh
        EOT
      ]
      environment = [
        { name = "GF_SECURITY_ADMIN_USER", value = "admin" },
        { name = "GF_SECURITY_ADMIN_PASSWORD", value = random_password.grafana_admin.result },
        { name = "GF_AUTH_ANONYMOUS_ENABLED", value = "false" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.monitoring.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "grafana"
        }
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_lb_target_group" "grafana" {
  name        = "${local.name_prefix}-grafana-tg"
  port        = var.grafana_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/api/health"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "grafana" {
  load_balancer_arn = var.alb_arn
  port              = var.grafana_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }
}

resource "aws_ecs_service" "monitoring" {
  name            = "${local.name_prefix}-monitoring-service"
  cluster         = var.ecs_cluster_name
  task_definition = aws_ecs_task_definition.monitoring.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.app_subnet_ids
    security_groups  = [aws_security_group.monitoring.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.grafana.arn
    container_name   = "grafana"
    container_port   = var.grafana_port
  }

  depends_on = [aws_lb_listener.grafana, aws_iam_role_policy_attachment.execution]
  tags       = local.common_tags
}