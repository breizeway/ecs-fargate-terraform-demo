# Declaring the default security group with no rules removes its default
# allow-all-between-members behaviour.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-default-locked" }
}

# Security groups. Rules reference other security groups instead of IP ranges
# where possible, so the app only accepts traffic from the load balancer.

resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-alb-"
  description = "Public load balancer: HTTP in from the internet, traffic out to the app only"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${var.project_name}-alb" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "app" {
  name_prefix = "${var.project_name}-app-"
  description = "App containers: only the load balancer may connect"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${var.project_name}-app" }

  lifecycle {
    create_before_destroy = true
  }
}

# Accepted exception (AWS-0107): a public web load balancer must accept traffic
# from the internet. Plain HTTP only for now; HTTPS needs a certificate and a
# domain name.
#trivy:ignore:AWS-0107
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from the internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "To app containers on 8000"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8000
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "From the load balancer on 8000"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8000
}

# Accepted exception (AWS-0104): there is no NAT gateway (~$30+/month), so tasks
# in public subnets reach ECR and CloudWatch over the internet gateway. Egress is
# limited to HTTPS. A production setup would use private subnets with VPC
# endpoints or a NAT gateway so tasks have no public IP at all.
#trivy:ignore:AWS-0104
resource "aws_vpc_security_group_egress_rule" "app_https_out" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS out: pull the image from ECR, ship logs to CloudWatch"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}
