variable "region" {
  description = "AWS region."
  type        = string
}

variable "environment" {
  description = "Environment name, applied as a tag to every resource."
  type        = string
}

variable "cluster_name" {
  description = "Cluster name; also names the VPC and ECR repository."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR range."
  type        = string
  default     = "10.0.0.0/16"
}

variable "kubernetes_version" {
  description = "EKS control plane version."
  type        = string
  default     = "1.31"
}

variable "instance_type" {
  description = "Worker node instance type."
  type        = string
  default     = "t3.small"
}

variable "node_count" {
  description = "Number of worker nodes."
  type        = number
  default     = 2
}

variable "image_tag_mutability" {
  description = "ECR tag mutability. IMMUTABLE in prod so a pushed tag can never be overwritten."
  type        = string
  default     = "MUTABLE"
}

variable "cluster_role_name" {
  description = "Existing IAM role for the control plane."
  type        = string
  default     = "eksClusterRole"
}

variable "node_role_name" {
  description = "Existing IAM role for worker nodes."
  type        = string
  default     = "eksNodeRole"
}
