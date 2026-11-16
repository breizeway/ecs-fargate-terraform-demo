output "app_url" {
  description = "Public address of the load balancer"
  value       = "http://${aws_lb.main.dns_name}"
}

output "ecr_repository_url" {
  description = "Where to push the image (make push reads this)"
  value       = aws_ecr_repository.app.repository_url
}
