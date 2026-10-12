# CS1-MA-NCA — Infrastructure as Code

Terraform configuration for Case Study 1 (Innovatech Solutions): a scalable
web environment on AWS, built as part of the CS1-MA-NCA case study (HBO ICT,
Fontys). Deployed and managed entirely through Terraform — no manual console
changes. Case Study 2 (CS2-MA-NCA) extends this environment into a hybrid
cloud with an on-prem environment and a SOAR system (see below).

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
- **Monitoring** — Prometheus + Grafana on ECS Fargate. Data sources and
  the dashboard are provisioned as code, so a replaced task comes back
  the same. CloudWatch alarms send e-mail via SNS.
- **CI/CD** — GitHub Actions on a self-hosted runner: an app pipeline
  (Build → Test → Push → Deploy) and an infra pipeline
  (Validate → Plan → Apply, Apply only when started manually).

## Repository structure

```
.
├── .github/workflows/
│   ├── deploy-app.yml      # Build → Test → Push → Deploy (changes in app/)
│   └── deploy-infra.yml    # Validate → Plan → Apply (changes in .tf / modules/)
├── app/                    # Dockerfile + website (Nginx)
├── main.tf                 # Root module: wires the modules together
├── providers.tf            # AWS + random provider configuration, state location
├── variables.tf            # Root-level variables (region, project name, environment)
├── outputs.tf              # Re-exposed outputs (ALB URL, Grafana URL, etc.)
├── modules/
│   ├── network/            # VPC, subnets, NAT Gateway, route tables, security groups
│   ├── compute/            # ECR, ECS cluster/service/task definition, ALB, Auto Scaling
│   ├── database/           # EC2 + MariaDB, Secrets Manager, SSM access for IT staff
│   ├── monitoring/         # Prometheus, Grafana (dashboard as code), alarms, SNS
│   ├── vpn/                # CS2: Site-to-Site VPN to NetLab
│   ├── dns/                # CS2: Route 53 private hosted zone
│   └── soar/               # CS2: SOAR platform (ECS service, S3, SNS, IAM)
├── soar/                   # CS2: Python SOAR service code and tests
├── ansible/                # CS2: configuration of NetLab VMs and OS updates
└── docs/                   # CS2: build steps for NetLab VMs and pfSense
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

## Case Study 2 (hybrid cloud, SOAR)

Case Study 2 extends this environment with Fontys NetLab (on-prem):

- `modules/vpn/` – Site-to-Site VPN between NetLab and the VPC
- `modules/dns/` – Route 53 private hosted zone `innovatech.internal`
- `modules/soar/`, `soar/` – the Python SOAR service
- `ansible/` – configuration of the NetLab VMs and OS updates
- `docs/` – build steps for the NetLab VMs and pfSense

Pipelines run on two self-hosted runners: the laptop (label `Windows`,
AWS pipelines) and mgmt01 in NetLab (label `Linux`, Ansible pipelines).

## Status

- ✅ Case Study 1 – all phases done (network, compute, database,
  monitoring, CI/CD, testing)
- ⏳ Case Study 2 – Phase 1 (design) done, Phase 2 in progress