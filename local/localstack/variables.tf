variable "region" {
  description = "Region. LocalStack ignores it, but the provider requires one."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for every resource name."
  type        = string
  default     = "lab"
}

variable "bucket_names" {
  description = "Bucket suffixes. Each becomes one bucket via for_each."
  type        = list(string)
  default     = ["logs", "artifacts", "backups"]

  validation {
    condition     = length(var.bucket_names) > 0
    error_message = "Provide at least one bucket name."
  }
}
