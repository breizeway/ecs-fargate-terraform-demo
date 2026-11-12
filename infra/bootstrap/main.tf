# Bootstrap stack: creates the S3 bucket that stores OpenTofu state for ../
#
# This stack keeps its own state in a local file (there is no `backend` block):
# the bucket cannot store its own state before it exists. The local state file
# is gitignored. If it is lost the bucket still exists and can be re-attached
# with `tofu import`.

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
  # AWS appends a random suffix, so the name is unique and contains no account
  # ID. The main stack receives the name at init time (see ../backend.hcl.example).
  bucket_prefix = "tfstate-"

  lifecycle {
    # Losing the state bucket means losing the record of everything it manages.
    # Remove this line deliberately when tearing the project down.
    prevent_destroy = true
  }
}

# Keep previous versions of the state file so a bad apply can be rolled back.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Accepted risk: S3-managed keys (AES256) instead of a customer-managed KMS key.
# The data is encrypted at rest; a KMS key would add key-level access control
# and audit logging, which a production or regulated setup should use.
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

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Refuse any request that is not made over TLS.
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

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.tls_only.json

  # AWS rejects bucket-policy changes that race with the public access block;
  # there is no attribute reference between them, so the order is explicit.
  depends_on = [aws_s3_bucket_public_access_block.state]
}
