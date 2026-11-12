provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "opentofu"
      Stack     = "main"
    }
  }
}

# Private image registry. ECS pulls the image from here using IAM permissions.
resource "aws_ecr_repository" "app" {
  name = var.project_name

  # Immutable tags: a pushed tag can never be overwritten, so what runs is
  # exactly what was tested. CI is expected to tag images with the commit SHA.
  image_tag_mutability = "IMMUTABLE"

  # Lab setting: lets `tofu destroy` remove the repository even when it holds
  # images. Leave this off for a repository that matters.
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Without a lifecycle policy every pushed image is kept (and billed) forever.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the 10 most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
