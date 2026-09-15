variable "name" {
  description = "Repository name."
  type        = string
}

variable "image_tag_mutability" {
  description = "MUTABLE lets a tag be overwritten. IMMUTABLE is the safer production setting."
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "Must be MUTABLE or IMMUTABLE."
  }
}

variable "retain_images" {
  description = "How many images to keep before expiring the oldest."
  type        = number
  default     = 10
}

variable "force_delete" {
  description = "Allow terraform destroy to remove the repo even when it still holds images."
  type        = bool
  default     = true
}
