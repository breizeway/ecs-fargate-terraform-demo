# ECS uses two roles:
#   execution role - used by ECS itself to pull the image and write logs
#   task role      - used by the application's own code (it needs no AWS access)

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "ecs_tasks_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    # Confused-deputy protection: only on behalf of this account.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${var.project_name}-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
}

# Least privilege: scoped to this repository and this log group, instead of the
# AWS-managed policy (which allows pulling from every repository).
# Accepted exception (AWS-0057): ecr:GetAuthorizationToken does not support
# resource-level permissions, so "*" is required for that one action; it returns
# only a short-lived login token.
#trivy:ignore:AWS-0057
data "aws_iam_policy_document" "task_execution" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PullOurImageOnly"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchCheckLayerAvailability",
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  statement {
    sid       = "WriteOurLogsOnly"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.app.arn}:*"]
  }
}

resource "aws_iam_role_policy" "task_execution" {
  name   = "pull-image-and-write-logs"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_execution.json
}

# The application makes no AWS API calls, so this role has no permissions. It
# exists so any future permission is added here deliberately and reviewed.
resource "aws_iam_role" "task" {
  name               = "${var.project_name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
}
