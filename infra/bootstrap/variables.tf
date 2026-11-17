variable "region" {
  description = "AWS region for the state bucket"
  type        = string
  default     = "us-west-2"
}

# New repositories get ID-based subjects (owner@id/repo@id) that survive renames and cannot be claimed by a later namespace owner, and the IDs are public. https://docs.github.com/en/actions/reference/security/oidc
variable "github_repository_subject" {
  description = "Repository part of the GitHub OIDC subject (the sub_claim_prefix without the repo: prefix) allowed to deploy"
  type        = string
  default     = "breizeway@70126993/ecs-fargate-terraform-demo@1450591666"
}
