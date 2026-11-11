terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # The bucket name is account-specific, so it is not committed. Supply it at
  # init time:  tofu init -backend-config=backend.hcl  (see backend.hcl.example).
  backend "s3" {
    key          = "ecs-fargate-demo/terraform.tfstate"
    region       = "us-west-2" # backend blocks cannot use variables
    encrypt      = true
    use_lockfile = true # S3-native state locking (OpenTofu/Terraform >= 1.10)
  }
}
