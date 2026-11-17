# Trivy flags every internet-facing load balancer; this one is the site's only public entry point, and the app accepts traffic only from it. https://docs.aws.amazon.com/elasticloadbalancing/latest/application/application-load-balancers.html
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

  # The default (300 s) makes every deploy slow; 30 s matches ECS's default stop timeout. https://docs.aws.amazon.com/elasticloadbalancing/latest/application/edit-target-group-attributes.html
  deregistration_delay = 30

  tags = { Name = var.project_name }
}

# Plain HTTP only redirects visitors to the HTTPS address. https://docs.aws.amazon.com/elasticloadbalancing/latest/application/rule-action-types.html
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
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

  # Redirect only once HTTPS is listening, or visitors would be sent to a port that is not open yet. https://opentofu.org/docs/language/meta-arguments/depends_on/
  depends_on = [aws_lb_listener.https]
}

# Accepts TLS 1.3 and 1.2 only, so older protocol versions are refused. https://docs.aws.amazon.com/elasticloadbalancing/latest/application/describe-ssl-policies.html
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.app.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
