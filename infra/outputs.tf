output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets, by availability zone"
  value       = { for az, subnet in aws_subnet.public : az => subnet.id }
}

output "ecr_repository_url" {
  description = "Where to push the image (the account ID is computed by AWS, not hard-coded)"
  value       = aws_ecr_repository.app.repository_url
}
