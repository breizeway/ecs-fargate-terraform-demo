variable "region" {
  description = "AWS region for the state bucket"
  type        = string
  default     = "us-west-2"
}

# Public already (it is in the remote URL); the trust policy pins deploys to this repository. https://docs.github.com/en/actions/reference/security/oidc
variable "github_repository" {
  description = "GitHub repository (owner/name) allowed to deploy"
  type        = string
  default     = "breizeway/ecs-fargate-terraform-demo"
}
