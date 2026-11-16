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

output "app_url" {
  description = "Public address of the load balancer"
  value       = "http://${aws_lb.main.dns_name}"
}

output "ecr_repository_url" {
  description = "Where to push the image (make push reads this)"
  value       = aws_ecr_repository.app.repository_url
}
