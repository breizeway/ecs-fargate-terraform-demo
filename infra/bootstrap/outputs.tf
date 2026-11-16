output "state_bucket_name" {
  description = "Name of the S3 bucket that stores state for the main stack"
  value       = aws_s3_bucket.state.id
}

output "github_deploy_role_arn" {
  description = "Role the deploy workflow assumes (store as the AWS_DEPLOY_ROLE_ARN secret)"
  value       = aws_iam_role.github_deploy.arn
}
