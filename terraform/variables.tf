variable "region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster; also used to name the ECR repo and VPC."
  type        = string
  default     = "platform-lab"
}

variable "kubernetes_version" {
  description = "EKS control plane version."
  type        = string
  default     = "1.31"
}

variable "instance_type" {
  description = "Worker node instance type. t3.small is 2 vCPU / 2GB with an 8-pod ENI ceiling."
  type        = string
  default     = "t3.small"
}

variable "node_count" {
  description = "Number of worker nodes. 2 x t3.small = 4 vCPU, under the 5 vCPU account quota."
  type        = number
  default     = 2

  validation {
    condition     = var.node_count >= 2
    error_message = "Use at least 2 nodes; a single node cannot demonstrate node-failure recovery."
  }
}

variable "cluster_role_name" {
  description = "Existing IAM role the EKS control plane assumes."
  type        = string
  default     = "eksClusterRole"
}

variable "node_role_name" {
  description = "Existing IAM role the worker nodes assume."
  type        = string
  default     = "eksNodeRole"
}
