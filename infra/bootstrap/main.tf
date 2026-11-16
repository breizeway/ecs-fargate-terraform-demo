# Creates the S3 bucket that stores OpenTofu state for ../ (this stack keeps its own state in a local, gitignored file).

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "region" {
  description = "AWS region for the state bucket"
  type        = string
  default     = "us-west-2"
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "ecs-fargate-demo"
      ManagedBy = "opentofu"
      Stack     = "bootstrap"
    }
  }
}

resource "aws_s3_bucket" "state" {
  # AWS adds a random suffix, so the name is unique and holds no account ID. https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket
  bucket_prefix = "tfstate-"

  lifecycle {
    # Losing this bucket means losing the record of everything the main stack manages. https://opentofu.org/docs/language/meta-arguments/lifecycle/
    prevent_destroy = true
  }
}

# Keeps old versions of the state file, so a bad apply can be rolled back. https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Accepted exception: AWS-managed keys instead of a KMS key, which would add key-level access control and audit logs. https://docs.aws.amazon.com/AmazonS3/latest/userguide/serv-side-encryption.html
#trivy:ignore:AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# State can contain secrets, so the bucket must never be public. https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html
resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

# Refuse any request that is not made over TLS. https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html
resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.tls_only.json

  # AWS rejects policy changes that race with the public access block, and nothing references it, so the order is stated. https://opentofu.org/docs/language/meta-arguments/depends_on/
  depends_on = [aws_s3_bucket_public_access_block.state]
}

output "state_bucket_name" {
  description = "Name of the S3 bucket that stores state for the main stack"
  value       = aws_s3_bucket.state.id
}
