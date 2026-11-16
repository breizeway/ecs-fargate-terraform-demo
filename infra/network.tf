data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  tags = { Name = var.project_name }
}

# cidrsubnet() gives each zone its own non-overlapping /24 (10.0.0.0/24, 10.0.1.0/24). https://opentofu.org/docs/language/functions/cidrsubnet/
resource "aws_subnet" "public" {
  for_each = { for index, az in local.azs : az => index }

  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, each.value)

  tags = { Name = "${var.project_name}-public-${each.key}" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = var.project_name }
}

# A subnet is "public" only because its route table sends internet traffic to the gateway. https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Internet_Gateway.html
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project_name}-public" }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}
