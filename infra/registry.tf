resource "aws_ecr_repository" "app" {
  name = var.project_name

  # A pushed tag can never be overwritten, so what runs is exactly what was tested. https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-tag-mutability.html
  image_tag_mutability = "IMMUTABLE"

  # Lab setting: lets `tofu destroy` delete the repository even when it still holds images. https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository
  force_delete = true

  # Each push is scanned for known vulnerabilities. https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-scanning.html
  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Without a lifecycle policy every pushed image is kept, and billed, forever. https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html
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
