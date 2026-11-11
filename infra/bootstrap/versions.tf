terraform {
  required_version = ">= 1.10" # S3-native state locking (used by ../) needs 1.10+

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "region" {
  description = "AWS region for the state bucket"
  type        = string
  default     = "us-west-2"
}
