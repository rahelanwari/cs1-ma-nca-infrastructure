module "network" {
  source = "./modules/network"

  project_name = var.project_name
  environment  = var.environment

  # Defaults from the module already match the Week 1 design
  # (10.0.0.0/16 VPC, 2 AZs, public/app/data subnets).
  # Override here if needed, e.g.:
  # availability_zones = ["eu-west-1a", "eu-west-1c"]
}

module "compute" {
  source = "./modules/compute"

  project_name = var.project_name
  environment  = var.environment

  vpc_id                 = module.network.vpc_id
  public_subnet_ids      = module.network.public_subnet_ids
  app_subnet_ids         = module.network.app_subnet_ids
  alb_security_group_id  = module.network.alb_security_group_id
  app_security_group_id  = module.network.app_security_group_id

  # Defaults already match Week 1 (baseline 2 tasks, peak up to 10,
  # scaling on 60% CPU). Override here if needed, e.g.:
  # container_image = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/innovatech-cs1-dev-nginx:latest"
}

# The database module (2.3 - self-managed MySQL-compatible database on EC2,
# after RDS was blocked by a Service Control Policy in this sandbox)

module "database" {
  source = "./modules/database"

  project_name = var.project_name
  environment  = var.environment

  data_subnet_ids       = module.network.data_subnet_ids
  db_security_group_id  = module.network.db_security_group_id
}
