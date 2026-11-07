# Private site bucket: only this distribution can read it, through origin access control.

resource "aws_s3_bucket" "site" {
  bucket = local.site_bucket
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "site_bucket" {
  statement {
    sid       = "CloudFrontOriginAccessControl"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site_bucket.json
  # S3 rejects concurrent bucket-policy and public-access-block writes (OperationAborted).
  depends_on = [aws_s3_bucket_public_access_block.site]
}

# Access logs (CloudFront standard logging, legacy S3 delivery; see docs/infra.md) and Athena
# query results. Everything in the bucket expires after 90 days.

resource "aws_s3_bucket" "logs" {
  bucket = local.logs_bucket
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# CloudFront standard logging delivers through a bucket ACL grant to its log-delivery account,
# so this bucket keeps ACLs enabled. CloudFront adds the grant itself when logging is enabled.
resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    id     = "expire-after-90-days"
    status = "Enabled"
    # Whole bucket: access logs under cloudfront/ and Athena results under athena-results/.
    filter {}
    expiration {
      days = 90
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}
