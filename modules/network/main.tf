data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

locals {
  region = data.aws_region.current.region

  # Public subnets take the first /prefix+4 blocks, private subnets start at block 8,
  # so a /16 VPC gives 10.x.0.0/20, 10.x.16.0/20 (public) and 10.x.128.0/20, ... (private).
  public_cidrs  = [for i, _ in var.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  private_cidrs = [for i, _ in var.azs : cidrsubnet(var.vpc_cidr, 4, i + 8)]

  endpoint_subnet_ids = var.single_az_endpoints ? [aws_subnet.private[0].id] : aws_subnet.private[*].id
}

################################################################################
# VPC and subnets
################################################################################

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # required for private DNS on interface endpoints

  tags = {
    Name = "${var.name}-vpc"
  }
}

# Take ownership of the default security group and strip all rules from it so
# nothing can accidentally use it.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-default-deny-all"
  }
}

resource "aws_subnet" "public" {
  count = length(var.azs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = false # only the ALB and the optional NAT live here

  tags = {
    Name = "${var.name}-public-${var.azs[count.index]}"
    Tier = "public"
  }
}

resource "aws_subnet" "private" {
  count = length(var.azs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.name}-private-${var.azs[count.index]}"
    Tier = "private"
  }
}

################################################################################
# Routing
################################################################################

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-public"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = length(var.azs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# One private route table is enough: there is at most one NAT gateway, and the
# S3 gateway endpoint attaches to route tables, not subnets.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-private"
  }
}

resource "aws_route_table_association" "private" {
  count = length(var.azs)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

################################################################################
# Optional NAT gateway (default off)
################################################################################

resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? 1 : 0

  domain = "vpc"

  tags = {
    Name = "${var.name}-nat"
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = var.enable_nat_gateway ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.name}-nat"
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route" "private_nat" {
  count = var.enable_nat_gateway ? 1 : 0

  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}
