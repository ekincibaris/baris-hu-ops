data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Fails the plan early if a pinned zone is unavailable in this account.
data "aws_availability_zones" "selected" {
  state = "available"

  filter {
    name   = "zone-name"
    values = var.availability_zones
  }
}

data "aws_route53_zone" "this" {
  name         = var.hosted_zone_name
  private_zone = false
}

locals {
  name        = "${var.project}-${var.environment}"
  azs         = sort(data.aws_availability_zones.selected.names)
  patch_group = "${local.name}-web"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    Service     = var.domain_name
    Owner       = var.owner_tag
    ManagedBy   = "terraform"
    Repository  = "ekincibaris/baris-hu-ops"
  }
}

module "network" {
  source = "../../modules/network"

  name                = local.name
  vpc_cidr            = var.vpc_cidr
  azs                 = local.azs
  enable_nat_gateway  = var.enable_nat_gateway
  single_az_endpoints = var.single_az_endpoints
  log_retention_days  = var.log_retention_days
  kms_key_arn         = aws_kms_key.this.arn
}

module "alb" {
  source = "../../modules/alb"

  name                       = local.name
  vpc_id                     = module.network.vpc_id
  public_subnet_ids          = module.network.public_subnet_ids
  target_cidrs               = module.network.private_subnet_cidrs
  domain_name                = var.domain_name
  zone_id                    = data.aws_route53_zone.this.zone_id
  enable_deletion_protection = var.enable_alb_deletion_protection
}

module "compute" {
  source = "../../modules/compute"

  name                               = local.name
  vpc_id                             = module.network.vpc_id
  vpc_cidr                           = module.network.vpc_cidr
  private_subnet_ids                 = module.network.private_subnet_ids
  s3_prefix_list_id                  = module.network.s3_prefix_list_id
  allow_internet_egress              = module.network.nat_gateway_enabled
  alb_security_group_id              = module.alb.alb_security_group_id
  target_group_arn                   = module.alb.target_group_arn
  instance_type                      = var.instance_type
  min_size                           = var.asg_min_size
  max_size                           = var.asg_max_size
  cpu_target_value                   = var.cpu_target_value
  patch_group                        = local.patch_group
  kms_key_arn                        = aws_kms_key.this.arn
  log_retention_days                 = var.log_retention_days
  manage_session_manager_preferences = var.manage_session_manager_preferences
  tags                               = local.common_tags
}

module "patching" {
  source = "../../modules/patching"

  name                        = local.name
  patch_group                 = local.patch_group
  maintenance_window_schedule = var.patch_schedule
  maintenance_window_timezone = var.patch_timezone
  run_command_log_group_name  = module.compute.run_command_log_group_name
}

module "monitoring" {
  source = "../../modules/monitoring"

  name                    = local.name
  alarm_email             = var.alarm_email
  kms_key_arn             = aws_kms_key.this.arn
  alb_arn_suffix          = module.alb.alb_arn_suffix
  target_group_arn_suffix = module.alb.target_group_arn_suffix
  asg_name                = module.compute.asg_name
  additional_alarm_arns   = [module.remediation.alarm_arn]
}

module "remediation" {
  source = "../../modules/remediation"

  name                           = local.name
  target_group_arn               = module.alb.target_group_arn
  target_group_arn_suffix        = module.alb.target_group_arn_suffix
  alb_arn_suffix                 = module.alb.alb_arn_suffix
  asg_name                       = module.compute.asg_name
  asg_arn                        = module.compute.asg_arn
  remediation_tag_key            = module.compute.remediation_tag_key
  sns_topic_arn                  = module.monitoring.sns_topic_arn
  run_command_log_group_name     = module.compute.run_command_log_group_name
  kms_key_arn                    = aws_kms_key.this.arn
  log_retention_days             = var.log_retention_days
  manage_automation_log_settings = var.manage_automation_log_settings
}
