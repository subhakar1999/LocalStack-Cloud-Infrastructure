resource "aws_s3_bucket" "bucket" {
  bucket        = var.bucket_name
  force_destroy = true

  tags = merge(
    var.tags,
    {
      Name        = var.bucket_name
      Environment = var.environment
    }
  )

  lifecycle {
    postcondition {
      condition     = alltrue([for key in ["Project", "Environment", "Name"] : try(length(trimspace(self.tags[key])) > 0, false)]) && (var.environment == "local" || !self.force_destroy)
      error_message = "S3-001: Require tags; force_destroy is only allowed locally."
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "ownership" {
  bucket = aws_s3_bucket.bucket.bucket

  rule {
    object_ownership = "BucketOwnerEnforced"
  }

  lifecycle {
    postcondition {
      condition     = self.rule[0].object_ownership == "BucketOwnerEnforced"
      error_message = "S3-003: Object ACLs must be disabled."
    }
  }
}

resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket = aws_s3_bucket.bucket.bucket

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  lifecycle {
    postcondition {
      condition     = self.block_public_acls && self.block_public_policy && self.ignore_public_acls && self.restrict_public_buckets
      error_message = "S3-002: All public access protections must be enabled."
    }
  }
}

resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.bucket.bucket

  versioning_configuration {
    status = "Enabled"
  }

  lifecycle {
    postcondition {
      condition     = self.versioning_configuration[0].status == "Enabled"
      error_message = "S3-004: Versioning must be enabled."
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sse" {
  bucket = aws_s3_bucket.bucket.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }

  lifecycle {
    postcondition {
      condition     = alltrue([for rule in self.rule : contains(["AES256", "aws:kms"], rule.apply_server_side_encryption_by_default[0].sse_algorithm)])
      error_message = "S3-005: Require AES256 or KMS encryption."
    }
  }
}
