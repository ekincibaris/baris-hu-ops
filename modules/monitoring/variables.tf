variable "name" {
  description = "Name prefix for every resource in this module, e.g. ops-baris-prod."
  type        = string
}

variable "alarm_email" {
  description = "Email address subscribed to the alarm topic. Keep it in terraform.tfvars (gitignored)."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[a-zA-Z]{2,}$", var.alarm_email))
    error_message = "alarm_email must be a valid email address."
  }
}

variable "kms_key_arn" {
  description = "Customer managed KMS key that encrypts the SNS topic."
  type        = string
}

variable "alb_arn_suffix" {
  description = "ARN suffix of the ALB (LoadBalancer dimension)."
  type        = string
}

variable "target_group_arn_suffix" {
  description = "ARN suffix of the target group (TargetGroup dimension)."
  type        = string
}

variable "asg_name" {
  description = "Name of the Auto Scaling group (AutoScalingGroupName dimension)."
  type        = string
}

variable "alb_5xx_threshold" {
  description = "Number of 5xx responses (ALB + targets) per minute that counts as a breaching datapoint."
  type        = number
  default     = 5
}

variable "cpu_alarm_threshold" {
  description = "Average CPU percent across the group that raises the high-CPU alarm. Keep it above the scaling target."
  type        = number
  default     = 80

  validation {
    condition     = var.cpu_alarm_threshold > 0 && var.cpu_alarm_threshold <= 100
    error_message = "cpu_alarm_threshold must be between 1 and 100."
  }
}

variable "unhealthy_sustained_minutes" {
  description = "Minutes a target must stay unhealthy before a human is paged (gives auto-remediation time to act first)."
  type        = number
  default     = 6

  validation {
    condition     = var.unhealthy_sustained_minutes >= 3 && var.unhealthy_sustained_minutes <= 60
    error_message = "unhealthy_sustained_minutes must be between 3 and 60."
  }
}

variable "additional_alarm_arns" {
  description = "Alarms owned by other modules (e.g. the remediation trigger) to show on the dashboard."
  type        = list(string)
  default     = []
}
