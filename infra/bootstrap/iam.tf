data "aws_caller_identity" "current" {}

# AWS accepts GitHub's signed tokens, so workflows get short-lived credentials and no access keys are stored. https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_deploy_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only jobs of this repository that run in the approval-gated "production" environment can assume the role. https://docs.github.com/en/actions/reference/security/oidc
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository_subject}:environment:production"]
    }
  }
}

# The name deliberately does not match the ecs-fargate-demo-* pattern below, so the role cannot edit itself.
resource "aws_iam_role" "github_deploy" {
  name                 = "gha-deploy-ecs-fargate-demo"
  assume_role_policy   = data.aws_iam_policy_document.github_deploy_trust.json
  max_session_duration = 3600
}

# Accepted exception: broad service access so `tofu apply` works without a long permission-tuning loop. https://docs.aws.amazon.com/aws-managed-policy/latest/reference/PowerUserAccess.html
resource "aws_iam_role_policy_attachment" "github_deploy_power_user" {
  role       = aws_iam_role.github_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "github_deploy_iam" {
  # PowerUserAccess excludes IAM, so only the project's own roles are allowed here, never admin roles or this one.
  statement {
    sid = "ManageProjectRolesOnly"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:ListRoleTags",
      "iam:TagRole",
      "iam:UntagRole",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/ecs-fargate-demo-*"]
  }

  # Passing a role is limited to ECS, so the role cannot hand its power to other services. https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_passrole.html
  statement {
    sid       = "PassProjectRolesToEcsOnly"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/ecs-fargate-demo-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "github_deploy_iam" {
  name   = "manage-project-roles-only"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy_iam.json
}
