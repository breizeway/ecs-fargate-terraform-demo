terraform {
  # use_lockfile (S3-native state locking) needs 1.10+. https://opentofu.org/docs/language/settings/backends/s3/
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # The bucket name is account-specific, so it is supplied at init time (see backend.hcl.example). https://opentofu.org/docs/language/settings/backends/configuration/
  backend "s3" {
    key = "ecs-fargate-demo/terraform.tfstate"
    # Backend blocks cannot use variables, so the region is repeated here. https://opentofu.org/docs/language/settings/backends/configuration/
    region       = "us-west-2"
    encrypt      = true
    use_lockfile = true
  }
}
