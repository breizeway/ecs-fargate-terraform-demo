# Public entry point: load balancer -> listener -> target group -> ECS tasks.

# Accepted exception (AWS-0053): this load balancer is the internet-facing entry
# point by design. The containers behind it only accept its security group.
#trivy:ignore:AWS-0053
resource "aws_lb" "main" {
  name               = var.project_name
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for subnet in aws_subnet.public : subnet.id]

  # Reject requests with malformed HTTP headers instead of forwarding them.
  drop_invalid_header_fields = true

  # Lab setting so `tofu destroy` can remove the (hourly-billed) load balancer.
  # Enable for production.
  enable_deletion_protection = false

  tags = { Name = var.project_name }
}

resource "aws_lb_target_group" "app" {
  name     = var.project_name
  vpc_id   = aws_vpc.main.id
  port     = 8000
  protocol = "HTTP"

  # Fargate tasks have their own network interface, so targets are IPs.
  target_type = "ip"

  # Healthy after 2 consecutive successes; removed from rotation after 3
  # failures. This is the health check that matters on ECS (the Dockerfile
  # HEALTHCHECK is ignored there).
  health_check {
    path                = "/healthz"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  # How long in-flight requests may finish after a task is deregistered. The
  # default (300s) makes deployments slow; 30s matches the app's graceful
  # shutdown (20s) and the ECS stop timeout (30s).
  deregistration_delay = 30

  tags = { Name = var.project_name }
}

# Accepted exception (AWS-0054): plain HTTP, because HTTPS needs a certificate
# (ACM) and a domain name. In production this listener would redirect to a
# port-443 listener that terminates TLS.
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
