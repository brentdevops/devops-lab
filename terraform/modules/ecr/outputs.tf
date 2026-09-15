output "repository_url" {
  description = "Push/pull URL for the registry."
  value       = aws_ecr_repository.app.repository_url
}

output "repository_name" {
  description = "Repository name."
  value       = aws_ecr_repository.app.name
}
