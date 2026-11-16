# Without a retention setting, logs are kept (and billed) forever. https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/Working-with-log-groups-and-streams.html
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

  # awsvpc gives each task its own network interface, so a security group attaches to the task itself. https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-task-networking.html
  network_mode = "awsvpc"

  cpu    = var.task_cpu
  memory = var.task_memory

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  execution_role_arn = aws_iam_role.task_execution.arn

  container_definitions = jsonencode([{
    name  = "app"
    image = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"

    portMappings = [{ containerPort = 8000 }]

    # The app writes nothing to disk, so make the filesystem read-only. https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html
    readonlyRootFilesystem = true

    # Seconds between SIGTERM and SIGKILL; longer than gunicorn's 20 s graceful_timeout. https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html
    stopTimeout = 30

    environment = [
      { name = "SERVICE_VERSION", value = var.image_tag },
    ]

    # The app logs to stdout; this driver ships it to CloudWatch. https://docs.aws.amazon.com/AmazonECS/latest/developerguide/using_awslogs.html
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
  launch_type     = "FARGATE"
  desired_count   = var.desired_count

  network_configuration {
    subnets         = [for subnet in aws_subnet.public : subnet.id]
    security_groups = [aws_security_group.app.id]

    # Public IP only so tasks can reach ECR and CloudWatch without a NAT gateway. https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-task-networking.html
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = 8000
  }

  # Rolling deploy: never drop below the desired count, start up to double while swapping. https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-type-ecs.html
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # A version that keeps failing to start is rolled back automatically. https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-circuit-breaker.html
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Ignore failed health checks while the app boots, or ECS kills tasks that are still starting. https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service_definition_parameters.html
  health_check_grace_period_seconds = 30

  # Nothing references the listener, so the order is stated: it must exist before the service registers. https://opentofu.org/docs/language/meta-arguments/depends_on/
  depends_on = [aws_lb_listener.http]
}
