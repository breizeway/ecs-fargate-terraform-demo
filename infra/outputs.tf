output "app_url" {
  description = "Public address of the site"
  value       = "https://${var.domain_name}"
}

output "ecr_repository_url" {
  description = "Where to push the image (make push reads this)"
  value       = aws_ecr_repository.app.repository_url
}

output "load_balancer_dns_name" {
  description = "Target of the CNAME record that points the site's name at the load balancer"
  value       = aws_lb.main.dns_name
}
