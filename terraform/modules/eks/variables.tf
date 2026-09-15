variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS control plane version."
  type        = string
  default     = "1.31"
}

variable "subnet_ids" {
  description = "Subnets for the control plane ENIs and worker nodes."
  type        = list(string)
}

variable "cluster_role_arn" {
  description = "IAM role ARN the control plane assumes."
  type        = string
}

variable "node_role_arn" {
  description = "IAM role ARN the worker nodes assume. Must carry ECR read permissions."
  type        = string
}

variable "instance_type" {
  description = "Worker node instance type."
  type        = string
  default     = "t3.small"
}

variable "node_count" {
  description = "Desired, min and max node count."
  type        = number
  default     = 2

  validation {
    condition     = var.node_count >= 2
    error_message = "Use at least 2 nodes so node-failure behaviour can be demonstrated."
  }
}

variable "network_dependency" {
  description = "Opaque value used only to order node creation after routing exists."
  type        = any
  default     = []
}
