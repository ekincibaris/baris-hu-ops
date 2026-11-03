variable "name" {
  description = "Name prefix for every resource in this module, e.g. ops-baris-prod."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR of the VPC; instances may reach the interface endpoints on 443 inside it."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets the Auto Scaling group launches into."
  type        = list(string)
}

variable "s3_prefix_list_id" {
  description = "Prefix list of the S3 gateway endpoint, allowed as an HTTPS egress destination."
  type        = string
}

variable "allow_internet_egress" {
  description = "Allow HTTP/HTTPS egress to 0.0.0.0/0. Only meaningful when the VPC has a NAT gateway."
  type        = bool
  default     = false
}

variable "alb_security_group_id" {
  description = "Security group of the ALB; the only allowed source of inbound traffic."
  type        = string
}

variable "target_group_arn" {
  description = "Target group the Auto Scaling group registers instances into."
  type        = string
}

variable "app_port" {
  description = "Port nginx listens on."
  type        = number
  default     = 80
}

variable "instance_type" {
  description = "EC2 instance type. Must be Graviton (arm64) to match the AMI parameter."
  type        = string
  default     = "t4g.micro"

  validation {
    condition     = can(regex("^[a-z]+[0-9]+g[a-z]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "Use a Graviton (arm64) instance type such as t4g.micro; the AMI is arm64."
  }
}

variable "ami_ssm_parameter" {
  description = "Public SSM parameter that resolves to the AMI at launch time (always the latest Amazon Linux 2023 build)."
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"

  validation {
    condition     = startswith(var.ami_ssm_parameter, "/aws/service/ami-amazon-linux-latest/al2023-")
    error_message = "The user data targets Amazon Linux 2023; use an /aws/service/ami-amazon-linux-latest/al2023-* parameter."
  }
}

variable "root_volume_size" {
  description = "Size of the encrypted gp3 root volume in GiB."
  type        = number
  default     = 10

  validation {
    condition     = var.root_volume_size >= 8 && var.root_volume_size <= 100
    error_message = "root_volume_size must be between 8 and 100 GiB."
  }
}

variable "min_size" {
  description = "Minimum number of instances in the Auto Scaling group."
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of instances in the Auto Scaling group."
  type        = number
  default     = 3

  validation {
    condition     = var.max_size >= var.min_size && var.max_size <= 10
    error_message = "max_size must be >= min_size and no more than 10."
  }
}

variable "cpu_target_value" {
  description = "Average CPU utilisation (percent) the target-tracking policy keeps the group at."
  type        = number
  default     = 50

  validation {
    condition     = var.cpu_target_value >= 10 && var.cpu_target_value <= 90
    error_message = "cpu_target_value must be between 10 and 90."
  }
}

variable "health_check_grace_period" {
  description = "Seconds after launch before Auto Scaling acts on health status."
  type        = number
  default     = 300
}

variable "patch_group" {
  description = "Value of the PatchGroup tag; links instances to the patch baseline and maintenance window."
  type        = string
}

variable "kms_key_arn" {
  description = "Customer managed KMS key for log groups and Session Manager encryption."
  type        = string
}

variable "log_retention_days" {
  description = "Retention in days for instance, Run Command and Session Manager log groups."
  type        = number
  default     = 365
}

variable "manage_session_manager_preferences" {
  description = "Create the account/region-wide SSM-SessionManagerRunShell document (session logging + KMS). Set false if it already exists and you do not want to import it."
  type        = bool
  default     = true
}

variable "session_idle_timeout_minutes" {
  description = "Session Manager idle timeout in minutes."
  type        = number
  default     = 20

  validation {
    condition     = var.session_idle_timeout_minutes >= 1 && var.session_idle_timeout_minutes <= 60
    error_message = "session_idle_timeout_minutes must be between 1 and 60."
  }
}

variable "tags" {
  description = "Tags copied onto instances, volumes and network interfaces (provider default_tags do not reach launch template tag_specifications)."
  type        = map(string)
  default     = {}
}
