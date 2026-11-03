variable "name" {
  description = "Name prefix for every resource in this module, e.g. ops-baris-prod."
  type        = string
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block of the VPC. Subnets are carved out as /prefix+4 blocks."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) >= 16 && tonumber(split("/", var.vpc_cidr)[1]) <= 24
    error_message = "vpc_cidr must be a valid IPv4 CIDR between /16 and /24."
  }
}

variable "azs" {
  description = "Availability zones to spread the public and private subnets across."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2 && length(var.azs) <= 4
    error_message = "Provide between 2 and 4 availability zones (an ALB needs at least 2)."
  }
}

variable "enable_nat_gateway" {
  description = "Create a single NAT gateway so private subnets get internet egress. Off by default: VPC endpoints cover everything the instances need."
  type        = bool
  default     = false
}

variable "single_az_endpoints" {
  description = "Place interface endpoints in the first private subnet only. Halves the endpoint bill for demos; instances in other AZs reach them cross-AZ and lose access if that AZ fails."
  type        = bool
  default     = false
}

variable "interface_endpoint_services" {
  description = "AWS services that get an interface VPC endpoint (short names, e.g. ssm)."
  type        = list(string)
  default     = ["ssm", "ssmmessages", "ec2messages", "logs", "monitoring"]

  validation {
    condition     = alltrue([for s in var.interface_endpoint_services : can(regex("^[a-z0-9.-]+$", s))])
    error_message = "Service names must be short endpoint names such as ssm or logs."
  }
}

variable "restrict_s3_endpoint_policy" {
  description = "Limit the S3 gateway endpoint to the AWS-owned buckets used by dnf, SSM Agent and Patch Manager. Set to false only while debugging package downloads."
  type        = bool
  default     = true
}

variable "flow_log_traffic_type" {
  description = "Traffic captured by VPC flow logs: ACCEPT, REJECT or ALL."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_log_traffic_type)
    error_message = "flow_log_traffic_type must be ACCEPT, REJECT or ALL."
  }
}

variable "log_retention_days" {
  description = "Retention in days for the flow log group."
  type        = number
  default     = 365
}

variable "kms_key_arn" {
  description = "ARN of the customer managed KMS key that encrypts the flow log group."
  type        = string
}
