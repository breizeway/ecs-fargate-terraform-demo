# Accepted exception: this is the internet-facing entry point by design; the app behind it only accepts this load balancer. https://docs.aws.amazon.com/elasticloadbalancing/latest/application/application-load-balancers.html
#trivy:ignore:AWS-0053
resource "aws_lb" "main" {
  name               = var.project_name
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for subnet in aws_subnet.public : subnet.id]

  # Reject requests with malformed HTTP headers instead of forwarding them. https://docs.aws.amazon.com/elasticloadbalancing/latest/application/application-load-balancers.html
  drop_invalid_header_fields = true

  tags = { Name = var.project_name }
}

resource "aws_lb_target_group" "app" {
  name     = var.project_name
  vpc_id   = aws_vpc.main.id
  port     = 8000
  protocol = "HTTP"

  # Fargate tasks have their own network interface, so targets are IP addresses. https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-target-groups.html
  target_type = "ip"

  # ECS ignores the Dockerfile HEALTHCHECK; this check decides who receives traffic. https://docs.aws.amazon.com/elasticloadbalancing/latest/application/target-group-health-checks.html
  health_check {
    path                = "/health"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  # The default (300 s) makes every deploy slow; 30 s matches the app's stop timeout. https://docs.aws.amazon.com/elasticloadbalancing/latest/application/edit-target-group-attributes.html
  deregistration_delay = 30

  tags = { Name = var.project_name }
}

# Accepted exception: plain HTTP until there is a domain and a certificate for HTTPS. https://docs.aws.amazon.com/elasticloadbalancing/latest/application/application-load-balancers.html
#trivy:ignore:AWS-0054
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
