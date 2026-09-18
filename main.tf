module "network" {
  source = "./modules/network"

  project_name = var.project_name
  environment  = var.environment
}

module "compute" {
  source = "./modules/compute"

  project_name = var.project_name
  environment  = var.environment

  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  app_subnet_ids        = module.network.app_subnet_ids
  alb_security_group_id = module.network.alb_security_group_id
  app_security_group_id = module.network.app_security_group_id
}

module "database" {
  source = "./modules/database"

  project_name = var.project_name
  environment  = var.environment

  data_subnet_ids      = module.network.data_subnet_ids
  db_security_group_id = module.network.db_security_group_id
}

module "monitoring" {
  source = "./modules/monitoring"

  project_name = var.project_name
  environment  = var.environment
  alert_email  = "560249@student.fontys.nl"

  vpc_id                = module.network.vpc_id
  app_subnet_ids        = module.network.app_subnet_ids
  alb_security_group_id = module.network.alb_security_group_id
  db_security_group_id  = module.network.db_security_group_id

  alb_arn                       = module.compute.alb_arn
  alb_arn_suffix                = module.compute.alb_arn_suffix
  alb_dns_name                  = module.compute.alb_dns_name
  nginx_target_group_arn_suffix = module.compute.nginx_target_group_arn_suffix
  ecs_cluster_name              = module.compute.ecs_cluster_name
  ecs_service_name              = module.compute.ecs_service_name

  db_private_ip = module.database.db_address
}
