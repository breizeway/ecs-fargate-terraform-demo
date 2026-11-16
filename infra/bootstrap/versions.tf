# Keeps its own state in a local, gitignored file: the state bucket cannot hold its own state before it exists. https://opentofu.org/docs/language/state/

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
