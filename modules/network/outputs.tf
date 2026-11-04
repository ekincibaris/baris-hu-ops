output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (ALB, optional NAT)."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (Auto Scaling group, interface endpoints)."
  value       = aws_subnet.private[*].id
}

output "private_subnet_cidrs" {
  description = "CIDR blocks of the private subnets."
  value       = aws_subnet.private[*].cidr_block
}

output "s3_prefix_list_id" {
  description = "Prefix list ID of the S3 gateway endpoint, for security group egress rules."
  value       = aws_vpc_endpoint.s3.prefix_list_id
}

output "interface_endpoint_ids" {
  description = "Map of service name to interface endpoint ID."
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.id }
}

output "nat_gateway_enabled" {
  description = "Whether private subnets have internet egress through a NAT gateway."
  value       = var.enable_nat_gateway
}

output "flow_log_group_name" {
  description = "CloudWatch log group that receives VPC flow logs."
  value       = aws_cloudwatch_log_group.flow_logs.name
}
