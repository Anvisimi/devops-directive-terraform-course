resource "aws_s3_bucket" "bucket" {
  bucket_prefix = var.bucket_prefix
  force_destroy = true #false for production
  tags = {
    Name        = "${var.bucket_prefix}-bucket"
    Environment = var.environment_name
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_versioning" "bucket_versioning" {
  bucket = aws_s3_bucket.bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bucket_crypto_conf" {
  bucket = aws_s3_bucket.bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "bucket_access" {
  bucket = aws_s3_bucket.bucket.id

  block_public_acls       = true   # ignore any ACL that grants public access
  block_public_policy     = true   # reject any bucket policy that grants public access
  ignore_public_acls      = true   # ignore existing public ACLs
  restrict_public_buckets = true   # restrict public access even if policy allows it
}
