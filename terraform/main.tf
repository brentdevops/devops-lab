terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  # Deliberately no default_tags here. Adding provider-level tags would make
  # `terraform plan` show an in-place update on every existing resource, which
  # hides whether the module refactor itself is clean. Add tags after the
  # refactor has been verified with a "No changes" plan.
}

# IAM roles were created by hand with the AWS CLI, so they are looked up
# rather than owned. Bringing them under Terraform with `terraform import`
# is a Phase 3 exercise.
data "aws_iam_role" "cluster" {
  name = var.cluster_role_name
}

data "aws_iam_role" "node" {
  name = var.node_role_name
}

module "vpc" {
  source = "./modules/vpc"

  name_prefix  = var.cluster_name
  cidr_block   = var.vpc_cidr
  subnet_count = 2
}

module "eks" {
  source = "./modules/eks"

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  subnet_ids         = module.vpc.public_subnet_ids
  cluster_role_arn   = data.aws_iam_role.cluster.arn
  node_role_arn      = data.aws_iam_role.node.arn
  instance_type      = var.instance_type
  node_count         = var.node_count

  network_dependency = module.vpc.route_table_association_ids
}

module "ecr" {
  source = "./modules/ecr"

  name                 = var.cluster_name
  image_tag_mutability = var.image_tag_mutability
  retain_images        = 10
}
