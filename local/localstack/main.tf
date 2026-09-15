terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# This provider block is the only thing that differs from real AWS.
# Every API call is redirected to LocalStack on localhost:4566.
provider "aws" {
  region     = var.region
  access_key = "test"
  secret_key = "test"

  # LocalStack does not validate credentials or account IDs.
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  s3_use_path_style           = true

  endpoints {
    s3       = "http://localhost:4566"
    dynamodb = "http://localhost:4566"
    iam      = "http://localhost:4566"
    sqs      = "http://localhost:4566"
    sts      = "http://localhost:4566"
    ec2      = "http://localhost:4566"
  }
}

# ---------------------------------------------------------------------------
# S3 buckets, created with for_each.
#
# for_each keys resources by a string instead of a number. That matters:
# with count, deleting the middle item renumbers everything after it and
# Terraform destroys and recreates them. With for_each, each resource is
# addressed by its own key and the others are untouched.
#
# Addresses look like: aws_s3_bucket.app["logs"]
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "app" {
  for_each = toset(var.bucket_names)
  bucket   = "${var.name_prefix}-${each.key}"
}

resource "aws_s3_bucket_versioning" "app" {
  for_each = aws_s3_bucket.app
  bucket   = each.value.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ---------------------------------------------------------------------------
# DynamoDB table.
#
# In a real setup this is the Terraform state lock table: one row is written
# while an apply runs, so a second person running apply is blocked instead of
# corrupting state.
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "locks" {
  name         = "${var.name_prefix}-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# ---------------------------------------------------------------------------
# SQS queue with a dead-letter queue.
#
# Messages that fail processing max_receive_count times move to the DLQ
# instead of being retried forever.
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "dlq" {
  name = "${var.name_prefix}-dlq"
}

resource "aws_sqs_queue" "main" {
  name                       = "${var.name_prefix}-queue"
  visibility_timeout_seconds = 30

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}

# ---------------------------------------------------------------------------
# IAM role and policy.
#
# The policy grants access only to the buckets created above, by referencing
# their ARNs. Hardcoding bucket names here would let the two drift apart.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "app" {
  name = "${var.name_prefix}-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "app" {
  name = "${var.name_prefix}-app-policy"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = [for b in aws_s3_bucket.app : "${b.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage", "sqs:ReceiveMessage"]
        Resource = [aws_sqs_queue.main.arn]
      }
    ]
  })
}
