variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name prefix for every resource."
  type        = string
  default     = "netlab"
}

variable "vpc_cidr" {
  description = "VPC CIDR. Subnets are carved out of this with cidrsubnet()."
  type        = string
  default     = "10.20.0.0/16"
}

variable "instance_type" {
  description = "App instance size. t3.micro is free-tier eligible."
  type        = string
  default     = "t3.micro"
}

variable "app_port" {
  description = "Port the app listens on. ALB and SG rules both follow this."
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "Path the ALB polls. Must return 200 or the target is drained."
  type        = string
  default     = "/healthz"
}
