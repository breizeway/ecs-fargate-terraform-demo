output "state_bucket_name" {
  description = "Name of the S3 bucket that stores state for the main stack"
  value       = aws_s3_bucket.state.id
}
