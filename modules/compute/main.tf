data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

locals {
  region     = data.aws_region.current.region
  account_id = data.aws_caller_identity.current.account_id

  # Known before the group exists, so the CloudWatch agent config and IAM
  # policies can reference it without a dependency cycle.
  asg_name = "${var.name}-web"

  instance_tags = merge(var.tags, {
    Name                 = "${var.name}-web"
    PatchGroup           = var.patch_group
    AutoRemediationGroup = local.asg_name
  })
}

################################################################################
# Security group: inbound only from the ALB, outbound only to the VPC
# endpoints (and the internet when a NAT gateway exists).
################################################################################

resource "aws_security_group" "instance" {
  name        = "${var.name}-web"
  description = "Status page instances: ALB in, VPC endpoints out"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-web"
  }
}

resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  #checkov:skip=CKV_AWS_260:False positive: the source is the ALB security group (referenced_security_group_id), not 0.0.0.0/0.
  security_group_id            = aws_security_group.instance.id
  description                  = "HTTP and health checks from the ALB"
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = var.alb_security_group_id
}

resource "aws_vpc_security_group_egress_rule" "endpoints" {
  security_group_id = aws_security_group.instance.id
  description       = "HTTPS to interface endpoints (SSM, CloudWatch)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_egress_rule" "s3" {
  security_group_id = aws_security_group.instance.id
  description       = "HTTPS to S3 through the gateway endpoint (dnf, Patch Manager)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = var.s3_prefix_list_id
}

resource "aws_vpc_security_group_egress_rule" "internet" {
  for_each = var.allow_internet_egress ? toset(["80", "443"]) : toset([])

  security_group_id = aws_security_group.instance.id
  description       = "Internet egress on ${each.value} through the NAT gateway"
  ip_protocol       = "tcp"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  cidr_ipv4         = "0.0.0.0/0"
}

################################################################################
# Launch template: AL2023 arm64, IMDSv2 only, no key pair, encrypted gp3.
################################################################################

resource "aws_launch_template" "this" {
  name_prefix            = "${var.name}-web-"
  description            = "Status page on Amazon Linux 2023 (arm64)"
  image_id               = "resolve:ssm:${var.ami_ssm_parameter}"
  instance_type          = var.instance_type
  update_default_version = true
  vpc_security_group_ids = [aws_security_group.instance.id]

  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh.tftpl", {
    cw_agent_parameter = aws_ssm_parameter.cw_agent_config.name
    app_port           = var.app_port
  }))

  iam_instance_profile {
    arn = aws_iam_instance_profile.this.arn
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  monitoring {
    enabled = true # 1-minute metrics so target tracking reacts quickly
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = local.instance_tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.instance_tags
  }

  tag_specifications {
    resource_type = "network-interface"
    tags          = local.instance_tags
  }

  tags = {
    Name = "${var.name}-web"
  }
}

################################################################################
# Auto Scaling group
################################################################################

# health_check_type = "EC2" is deliberate. The auto-remediation runbook owns
# application failures: it restarts the service first and only then marks the
# instance Unhealthy itself. With "ELB" health checks the group would terminate
# the instance before the restart could run, and the two automations would race.
# See README "Auto-remediation".
resource "aws_autoscaling_group" "this" {
  name                      = local.asg_name
  min_size                  = var.min_size
  max_size                  = var.max_size
  vpc_zone_identifier       = var.private_subnet_ids
  target_group_arns         = [var.target_group_arn]
  health_check_type         = "EC2"
  health_check_grace_period = var.health_check_grace_period
  default_instance_warmup   = 120
  wait_for_capacity_timeout = "15m"

  launch_template {
    id      = aws_launch_template.this.id
    version = aws_launch_template.this.latest_version
  }

  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupMaxSize",
    "GroupMinSize",
    "GroupPendingInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances",
  ]
  metrics_granularity = "1Minute"

  # A launch template change rolls the group, launching the replacement before
  # terminating the old instance so a min_size=1 group keeps serving.
  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 100
      max_healthy_percentage = 200
      instance_warmup        = 120
    }
  }

  dynamic "tag" {
    for_each = local.instance_tags

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = false # instances are tagged by the launch template
    }
  }

  lifecycle {
    ignore_changes = [desired_capacity] # owned by the scaling policy
  }

  depends_on = [
    aws_iam_role_policy.instance,
    aws_cloudwatch_log_group.this,
  ]
}

resource "aws_autoscaling_policy" "cpu_target" {
  name                   = "${var.name}-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.this.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    target_value = var.cpu_target_value

    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
  }
}
