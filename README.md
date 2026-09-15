# CS1-MA-NCA — Infrastructure as Code

Terraform configuration for Case Study 1 (Innovatech Solutions): a scalable
web environment on AWS, built as part of the CS1-MA-NCA case study (HBO ICT,
Fontys). Deployed and managed entirely through Terraform — no manual console
changes.

## Architecture

- **Network** — a VPC (`10.0.0.0/16`) with public, app-tier, and data-tier
  subnets across 2 Availability Zones, a single NAT Gateway, and 3 Security
  Groups enforcing strict tier-to-tier access (REQ-NCA-P1-01 / 02).
- **Compute** — Nginx running on ECS Fargate behind an Application Load
  Balancer, with Auto Scaling (2–10 tasks, target-tracking on 60% CPU)
  implementing REQ-NCA-P1-04.
- **Database** — a self-managed MySQL-compatible database (MariaDB) on EC2,
  in the private data-tier subnet. This replaces the originally planned RDS
  instance, which was blocked by an organization-level Service Control
  Policy in the AWS Innovation Sandbox used for this case study. IT staff
  access is provided via AWS Systems Manager Session Manager — no SSH key,
  no open inbound port, IAM-authenticated and fully logged.

## Repository structure

```
.
├── main.tf            # Root module: wires network, compute, and database together
├── providers.tf        # AWS + random provider configuration
├── variables.tf         # Root-level variables (region, project name, environment)
├── outputs.tf            # Re-exposed outputs (ALB URL, DB endpoint, etc.)
└── modules/
    ├── network/           # VPC, subnets, NAT Gateway, route tables, security groups
    ├── compute/            # ECR, ECS cluster/service/task definition, ALB, Auto Scaling
    └── database/            # EC2 + MariaDB, Secrets Manager, SSM access for IT staff
```

## Prerequisites

- Terraform >= 1.5.0
- AWS credentials for the target sandbox/account
- An AWS CloudShell session or local terminal with the AWS CLI configured

## Deploying

```bash
terraform init
terraform plan
terraform apply
```

Region defaults to `eu-west-1` (Ireland) — override via the `aws_region`
variable if deploying elsewhere.

## Cost note

The NAT Gateway and EC2 instance incur cost even when idle. Run
`terraform destroy` between work sessions if working within a limited
sandbox budget.

## Notes on deviations from the original design

- **Database:** originally designed as RDS MySQL. Switched to a
  self-managed EC2 + MariaDB setup after RDS `CreateDBInstance` was denied
  by a sandbox-level Service Control Policy. Network placement and security
  group rules are unchanged from the original design.
- **IT staff access:** added after re-reading the assignment text for 2.3
  ("...accessible by the web servers **and IT staff**"), which the initial
  RDS/EC2 design didn't yet provide a route for. Implemented via an IAM
  role + instance profile granting Session Manager access.

## Status

- ✅ Phase 2 (Network, Compute, Database) — deployed and verified
- ⏳ Phase 3 (Monitoring, CI/CD) — in progress
