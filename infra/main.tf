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
