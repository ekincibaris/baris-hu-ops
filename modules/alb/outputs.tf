output "alb_arn" {
  description = "ARN of the Application Load Balancer."
  value       = aws_lb.this.arn
}

output "alb_arn_suffix" {
  description = "ARN suffix of the ALB, used as the LoadBalancer dimension in CloudWatch."
  value       = aws_lb.this.arn_suffix
}

output "alb_dns_name" {
  description = "DNS name AWS assigned to the ALB."
  value       = aws_lb.this.dns_name
}

output "alb_security_group_id" {
  description = "Security group ID of the ALB, used as the source for instance ingress."
  value       = aws_security_group.alb.id
}

output "target_group_arn" {
  description = "ARN of the target group the Auto Scaling group registers into."
  value       = aws_lb_target_group.this.arn
}

output "target_group_arn_suffix" {
  description = "ARN suffix of the target group, used as the TargetGroup dimension in CloudWatch."
  value       = aws_lb_target_group.this.arn_suffix
}

output "url" {
  description = "Public HTTPS URL of the site."
  value       = "https://${var.domain_name}"
}

output "certificate_arn" {
  description = "ARN of the validated ACM certificate."
  value       = aws_acm_certificate_validation.this.certificate_arn
}

output "access_log_bucket" {
  description = "Name of the S3 bucket that stores ALB access logs."
  value       = aws_s3_bucket.access_logs.id
}
