# An empty default security group removes its allow-all-between-members behaviour. https://docs.aws.amazon.com/vpc/latest/userguide/default-security-group.html
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-default-locked" }
}

# name_prefix + create_before_destroy lets a replacement group exist alongside the old one. https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
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

# Accepted exception: a public website must accept the internet; HTTPS arrives with the custom domain. https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-update-security-groups.html
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

# Referencing the load balancer's group (not an IP range) means only the load balancer can reach the app. https://docs.aws.amazon.com/vpc/latest/userguide/security-group-rules.html
resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "From the load balancer on 8000"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8000
}

# Accepted exception: no NAT gateway (about $30/month), so tasks reach ECR and CloudWatch over the internet gateway on 443 only. https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-task-networking.html
#trivy:ignore:AWS-0104
resource "aws_vpc_security_group_egress_rule" "app_https_out" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS out: pull the image from ECR, ship logs to CloudWatch"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}
