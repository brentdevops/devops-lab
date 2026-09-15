# Production environment.
#
# NOT APPLIED. Running this creates a second cluster and a second control
# plane charge (~$73/month). It exists to demonstrate the pattern: one set of
# modules, different inputs per environment.
#
# Note it also uses a different VPC CIDR, so the two environments could be
# peered later without overlapping address space.

region       = "us-east-1"
environment  = "prod"
cluster_name = "platform-lab-prod"

kubernetes_version = "1.31"
instance_type      = "t3.medium"
node_count         = 3
vpc_cidr           = "10.1.0.0/16"

# Immutable in production: once a tag is pushed it can never be overwritten,
# so a given tag always refers to exactly one image. This is what makes
# "roll back to the previous tag" trustworthy.
image_tag_mutability = "IMMUTABLE"
