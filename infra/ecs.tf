# ECS vocabulary:
#   cluster          - logical grouping (with Fargate there are no servers to manage)
#   task definition  - the recipe for one copy: image, CPU/memory, ports, logs, roles
#   service          - keeps N tasks running, registers them with the load balancer,
#                      and rolls out new task-definition revisions

# Without a retention setting, logs are kept (and billed) forever.
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 14
}

resource "aws_ecs_cluster" "main" {
  name = var.project_name
}

resource "aws_ecs_task_definition" "app" {
  family                   = var.project_name
  requires_compatibilities = ["FARGATE"]

  # awsvpc gives each task its own network interface and IP, so the security
  # group attaches to the task and the target group can use IP targets.
  network_mode = "awsvpc"

  cpu    = var.task_cpu
  memory = var.task_memory

  # Must match the architecture the image was built for, or the task fails at
  # start-up with "exec format error".
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  execution_role_arn = aws_iam_role.task_execution.arn
  task_role_arn      = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = "app"
    image     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
    essential = true

    portMappings = [{
      containerPort = 8000
      protocol      = "tcp"
    }]

    # The application writes nothing to disk (gunicorn's heartbeat files use
    # /dev/shm, which stays writable).
    readonlyRootFilesystem = true

    # Seconds between SIGTERM and SIGKILL; longer than gunicorn's graceful_timeout.
    stopTimeout = 30

    environment = [
      { name = "SERVICE_VERSION", value = var.image_tag },
    ]

    # The application logs to stdout/stderr; the execution role allows the write.
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "app"
      }
    }
  }])
}

resource "aws_ecs_service" "app" {
  name            = var.project_name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [for subnet in aws_subnet.public : subnet.id]
    security_groups = [aws_security_group.app.id]

    # Accepted trade-off: tasks get a public IP only so they can reach ECR and
    # CloudWatch without a NAT gateway. The security group still allows inbound
    # traffic only from the load balancer.
    assign_public_ip = true
  }

  # ECS registers each task's IP with the target group and removes it when the
  # task stops; the load balancer health-checks it before sending traffic.
  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = 8000
  }

  # Rolling deployments without dropping below the desired capacity.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # Stop retrying a deployment that keeps failing and roll back to the last good one.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Failed health checks during start-up are ignored for this long.
  health_check_grace_period_seconds = 30

  # The listener must exist before the service registers with the target group;
  # nothing references it directly, so the dependency is explicit.
  depends_on = [aws_lb_listener.http]
}
