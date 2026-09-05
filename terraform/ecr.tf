# Private registry for the app image.
#
# Your EKS nodes can pull from this with no imagePullSecret at all, because
# eksNodeRole carries AmazonEC2ContainerRegistryReadOnly. That is the answer
# to "how does the cluster authenticate to ECR?" — the node instance role,
# not a Kubernetes secret.

resource "aws_ecr_repository" "app" {
  name = var.cluster_name

  # MUTABLE lets CI overwrite a tag. IMMUTABLE is the safer production choice:
  # it makes a pushed tag permanent, so a given tag always means one image.
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true # free basic CVE scanning
  }

  force_delete = true # lets `terraform destroy` remove it with images inside
}

# Keep only the 10 most recent images. Without this, ECR storage grows
# forever and every CI run adds to the bill.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
