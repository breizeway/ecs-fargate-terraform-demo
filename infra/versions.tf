terraform {
  # use_lockfile (S3-native state locking) needs 1.10+. https://opentofu.org/docs/language/settings/backends/s3/
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Left out on purpose (a partial configuration): the bucket name is account-specific, so `tofu init` reads it from backend.hcl. https://opentofu.org/docs/language/settings/backends/configuration/
  backend "s3" {
    key = "ecs-fargate-demo/terraform.tfstate"
    # Written out because Terraform rejects variables in backend blocks, and this code stays compatible with it. https://developer.hashicorp.com/terraform/language/backend
    region       = "us-west-2"
    encrypt      = true
    use_lockfile = true
  }
}
