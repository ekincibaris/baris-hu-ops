variable "name" {
  description = "Name prefix for every resource in this module, e.g. ops-baris-prod."
  type        = string

  validation {
    # ALB and target group names are limited to 32 characters; the longest suffix used here is "-tg" / "-alb".
    condition     = length(var.name) <= 28
    error_message = "name must be 28 characters or fewer so the ALB and target group names fit AWS limits."
  }
}

variable "vpc_id" {
  description = "ID of the VPC the load balancer lives in."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets for the internet-facing ALB (at least two AZs)."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "An Application Load Balancer needs subnets in at least two availability zones."
  }
}

variable "target_cidrs" {
  description = "CIDR blocks the ALB may reach on the target port (the private subnets)."
  type        = list(string)
}

variable "target_port" {
  description = "Port the application listens on inside the instances."
  type        = number
  default     = 80
}

variable "health_check_path" {
  description = "HTTP path the target group polls on each instance."
  type        = string
  default     = "/health"
}

variable "domain_name" {
  description = "Fully qualified domain name served by the ALB, e.g. ops.baris.hu."
  type        = string
}

variable "zone_id" {
  description = "ID of the existing Route 53 hosted zone that contains domain_name."
  type        = string
}

variable "ssl_policy" {
  description = "TLS security policy for the HTTPS listener."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"
}

variable "enable_deletion_protection" {
  description = "Protect the ALB against deletion. Off by default because this environment is destroyed after every demo."
  type        = bool
  default     = false
}

variable "access_log_retention_days" {
  description = "Days to keep ALB access logs in S3."
  type        = number
  default     = 30
}
