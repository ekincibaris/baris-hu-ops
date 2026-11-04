variable "allowed_account_ids" {
  description = "AWS account IDs this configuration may be applied to. Set in terraform.tfvars."
  type        = list(string)

  validation {
    condition     = length(var.allowed_account_ids) > 0 && alltrue([for id in var.allowed_account_ids : can(regex("^[0-9]{12}$", id))])
    error_message = "Provide at least one 12-digit AWS account ID."
  }
}

variable "region" {
  description = "AWS region for every resource."
  type        = string
  default     = "eu-central-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must look like eu-central-1."
  }
}

variable "project" {
  description = "Short project name used in resource names and tags."
  type        = string
  default     = "ops-baris"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,15}$", var.project))
    error_message = "project must be 3-16 lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Environment name used in resource names and tags."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "owner_tag" {
  description = "Team or role that owns the stack (Owner tag). Not a personal name or email."
  type        = string
  default     = "cloudops"
}

variable "hosted_zone_name" {
  description = "Existing public Route 53 hosted zone (not created here)."
  type        = string
  default     = "baris.hu"
}

variable "domain_name" {
  description = "FQDN of the site; must be inside hosted_zone_name."
  type        = string
  default     = "ops.baris.hu"

  validation {
    condition     = endswith(var.domain_name, ".${trimsuffix(var.hosted_zone_name, ".")}")
    error_message = "domain_name must be a subdomain of hosted_zone_name."
  }
}

variable "alarm_email" {
  description = "Email that receives alarm notifications. Set in terraform.tfvars (gitignored); confirm the subscription email after apply."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[a-zA-Z]{2,}$", var.alarm_email))
    error_message = "alarm_email must be a valid email address."
  }
}

variable "vpc_cidr" {
  description = "IPv4 CIDR of the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones to use, pinned by name so the layout never changes when AWS adds a zone."
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b"]

  validation {
    condition     = length(var.availability_zones) >= 2 && length(var.availability_zones) <= 3 && alltrue([for z in var.availability_zones : startswith(z, var.region)])
    error_message = "Provide 2 or 3 availability zones in the selected region."
  }
}

variable "enable_nat_gateway" {
  description = "Add one NAT gateway for internet egress from private subnets. Not needed: VPC endpoints cover SSM, CloudWatch and dnf."
  type        = bool
  default     = false
}

variable "single_az_endpoints" {
  description = "Put the interface endpoints in one AZ only. Cheaper demo deployments; not resilient to that AZ failing."
  type        = bool
  default     = false
}

variable "instance_type" {
  description = "Graviton instance type for the web tier."
  type        = string
  default     = "t4g.micro"

  validation {
    condition     = can(regex("^[a-z]+[0-9]+g[a-z]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "Use a Graviton (arm64) instance type such as t4g.micro; the AMI is arm64."
  }
}

variable "asg_min_size" {
  description = "Minimum number of web instances."
  type        = number
  default     = 1

  validation {
    condition     = var.asg_min_size >= 1
    error_message = "asg_min_size must be at least 1."
  }
}

variable "asg_max_size" {
  description = "Maximum number of web instances."
  type        = number
  default     = 3

  validation {
    condition     = var.asg_max_size >= var.asg_min_size
    error_message = "asg_max_size must be greater than or equal to asg_min_size."
  }
}

variable "cpu_target_value" {
  description = "Average CPU percent that target tracking keeps the group at."
  type        = number
  default     = 50
}

variable "patch_schedule" {
  description = "Maintenance window schedule for installing patches."
  type        = string
  default     = "cron(0 3 ? * SUN *)"
}

variable "patch_timezone" {
  description = "Time zone of patch_schedule."
  type        = string
  default     = "Europe/Budapest"
}

variable "log_retention_days" {
  description = "Retention for every CloudWatch log group in the stack."
  type        = number
  default     = 365

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch Logs accepts (e.g. 30, 90, 365)."
  }
}

variable "manage_session_manager_preferences" {
  description = "Manage the account-wide SSM-SessionManagerRunShell document (session logging and KMS encryption)."
  type        = bool
  default     = true
}

variable "manage_automation_log_settings" {
  description = "Manage the account-wide SSM Automation script log settings (send aws:executeScript output to CloudWatch Logs)."
  type        = bool
  default     = true
}

variable "enable_alb_deletion_protection" {
  description = "Turn on ALB deletion protection (turn off again before terraform destroy)."
  type        = bool
  default     = false
}
