output "app_url" {
  description = "Public address of the site"
  value       = "https://${var.domain_name}"
}

output "ecr_repository_url" {
  description = "Where to push the image (make push reads this)"
  value       = aws_ecr_repository.app.repository_url
}

output "name_servers" {
  description = "Add these as NS records for the subdomain at the parent domain's DNS provider"
  value       = aws_route53_zone.app.name_servers
}
