################################################################################
# S3 gateway endpoint (free): dnf repositories for Amazon Linux 2023, SSM Agent
# and Patch Manager artefacts are all served from AWS-owned S3 buckets.
################################################################################

locals {
  # Buckets documented by AWS for AL2023 package repositories and for SSM Agent /
  # Patch Manager. Everything else in S3 is unreachable from the private subnets.
  s3_endpoint_allowed_objects = [
    "arn:aws:s3:::al2023-repos-${local.region}-de612dc2/*",
    "arn:aws:s3:::amazon-ssm-${local.region}/*",
    "arn:aws:s3:::amazon-ssm-packages-${local.region}/*",
    "arn:aws:s3:::${local.region}-birdwatcher-prod/*",
    "arn:aws:s3:::aws-ssm-${local.region}/*",
    "arn:aws:s3:::aws-ssm-distributor-file-${local.region}/*",
    "arn:aws:s3:::aws-ssm-document-attachments-${local.region}/*",
    "arn:aws:s3:::patch-baseline-snapshot-${local.region}/*",
    "arn:aws:s3:::aws-patch-manager-${local.region}-*/*",
    "arn:aws:s3:::amazoncloudwatch-agent-${local.region}/*",
  ]
}

data "aws_iam_policy_document" "s3_endpoint" {
  statement {
    sid       = "AllowAwsOwnedRepositoryBuckets"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = local.s3_endpoint_allowed_objects

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${local.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
  policy            = var.restrict_s3_endpoint_policy ? data.aws_iam_policy_document.s3_endpoint.json : null

  tags = {
    Name = "${var.name}-s3"
  }
}

################################################################################
# Interface endpoints: SSM (Session Manager, Run Command, Patch Manager),
# CloudWatch Logs and CloudWatch metrics.
################################################################################

resource "aws_security_group" "endpoints" {
  name        = "${var.name}-vpc-endpoints"
  description = "HTTPS from inside the VPC to the interface endpoints"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.name}-vpc-endpoints"
  }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  security_group_id = aws_security_group.endpoints.id
  description       = "HTTPS from the VPC"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = aws_vpc.this.cidr_block
}

# No egress rules: endpoint ENIs only answer requests, and security groups are
# stateful, so responses are allowed without an explicit rule.

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.interface_endpoint_services)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${local.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.endpoint_subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.name}-${each.value}"
  }
}
