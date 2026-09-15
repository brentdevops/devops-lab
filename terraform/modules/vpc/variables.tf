variable "name_prefix" {
  description = "Prefix for resource names and tags."
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR range."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_count" {
  description = "Number of public subnets, one per AZ. EKS requires at least 2."
  type        = number
  default     = 2

  validation {
    condition     = var.subnet_count >= 2
    error_message = "EKS requires subnets in at least two availability zones."
  }
}
