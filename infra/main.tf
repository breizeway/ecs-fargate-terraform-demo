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
    key          = "ecs-fargate-demo/terraform.tfstate"
    region       = "us-west-2" # backend blocks cannot use variables
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  # Tags every resource, so cost and ownership can be traced. https://registry.terraform.io/providers/hashicorp/aws/latest/docs/guides/resource-tagging
  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "opentofu"
      Stack     = "main"
    }
  }
}

variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Name used for resources and tags"
  type        = string
  default     = "ecs-fargate-demo"
}

# No default, so every deploy names the exact image version (CI will pass the commit SHA). https://opentofu.org/docs/language/values/variables/
variable "image_tag" {
  description = "Tag of the image in ECR to run"
  type        = string
}

output "app_url" {
  description = "Public address of the load balancer"
  value       = "http://${aws_lb.main.dns_name}"
}

output "ecr_repository_url" {
  description = "Where to push the image (make push reads this)"
  value       = aws_ecr_repository.app.repository_url
}
