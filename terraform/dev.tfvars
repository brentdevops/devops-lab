# Development environment.
# These values MUST match the currently running cluster exactly, or the
# refactor plan will propose changes instead of reporting "No changes."

region       = "us-east-1"
environment  = "dev"
cluster_name = "platform-lab"

kubernetes_version = "1.31"
instance_type      = "t3.small"
node_count         = 2
vpc_cidr           = "10.0.0.0/16"

# Mutable tags are tolerable in dev, where overwriting a tag is a convenience.
image_tag_mutability = "MUTABLE"
