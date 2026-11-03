data "aws_caller_identity" "current" {}

################################################################################
# Security group: HTTPS and HTTP (redirect only) from the internet,
# plain HTTP to the private subnets on the target port.
################################################################################

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Internet-facing ALB for ${var.domain_name}"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-alb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from the internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  #checkov:skip=CKV_AWS_260:Port 80 is open only so the listener can return a 301 to HTTPS; no content is ever served over HTTP.
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from the internet, redirected to HTTPS"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "targets" {
  for_each = toset(var.target_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "Forward traffic and health checks to targets in ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.target_port
  to_port           = var.target_port
  cidr_ipv4         = each.value
}

################################################################################
# Load balancer
################################################################################

resource "aws_lb" "this" {
  #checkov:skip=CKV2_AWS_28:WAF costs ~5 EUR/month plus per-rule fees; out of scope for a static status page. Documented as a follow-up in the README.
  #checkov:skip=CKV_AWS_150:Deletion protection is a variable (enable_deletion_protection), off by default because the demo environment is destroyed after use.
  name               = "${var.name}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  drop_invalid_header_fields = true
  enable_deletion_protection = var.enable_deletion_protection
  idle_timeout               = 60

  access_logs {
    bucket  = aws_s3_bucket.access_logs.id
    prefix  = "alb"
    enabled = true
  }

  depends_on = [aws_s3_bucket_policy.access_logs]
}

# Plain HTTP to the targets is deliberate: TLS terminates at the ALB and the
# last hop stays inside the private subnets. End-to-end TLS would need a
# certificate on every instance.
resource "aws_lb_target_group" "this" {
  name                 = "${var.name}-tg"
  vpc_id               = var.vpc_id
  port                 = var.target_port
  protocol             = "HTTP"
  target_type          = "instance"
  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = aws_acm_certificate_validation.this.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
