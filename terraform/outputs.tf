output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "ecr_repository_url" {
  description = "Push target for the app image."
  value       = module.ecr.repository_url
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "kubeconfig_command" {
  description = "Point kubectl at this cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
