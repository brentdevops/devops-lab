output "bucket_names" {
  description = "Created bucket names, keyed the same way as for_each."
  value       = { for k, b in aws_s3_bucket.app : k => b.id }
}

output "queue_url" {
  description = "Main SQS queue URL."
  value       = aws_sqs_queue.main.url
}

output "lock_table" {
  description = "DynamoDB table name."
  value       = aws_dynamodb_table.locks.name
}

output "role_arn" {
  description = "IAM role ARN."
  value       = aws_iam_role.app.arn
}
