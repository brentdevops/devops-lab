terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Phase 1 uses local state on purpose, so you can open terraform.tfstate
  # and read it. Phase 2 moves this to an S3 backend with DynamoDB locking.
}

provider "aws" {
  region = var.region
}

# Two AZs. EKS refuses to create a cluster in a single AZ.
data "aws_availability_zones" "available" {
  state = "available"
}

# You created these roles by hand with the AWS CLI, so Terraform looks them up
# rather than owning them. Bringing them under Terraform management later with
# `terraform import` is a deliberate exercise.
data "aws_iam_role" "cluster" {
  name = var.cluster_role_name
}

data "aws_iam_role" "node" {
  name = var.node_role_name
}

# ---------------------------------------------------------------------------
# Network
#
# Public subnets only. A NAT Gateway would cost ~$32/month and buys nothing
# for a lab. The tradeoff: worker nodes get public IPs. Real production puts
# nodes in private subnets behind NAT — know how to say that out loud.
# ---------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true # required for EKS node registration
  tags                 = { Name = "${var.cluster_name}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.cluster_name}-igw" }
}

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true # nodes need a public IP to reach the EKS API

  tags = {
    Name = "${var.cluster_name}-public-${count.index}"
    # EKS looks for this tag to decide where it may place load balancers.
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.cluster_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# EKS control plane
#
# This is the resource that takes ~10 minutes and costs ~$0.10/hour.
# ---------------------------------------------------------------------------

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = data.aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = aws_subnet.public[*].id
    endpoint_public_access  = true
    endpoint_private_access = false
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
    # Grants the identity running `terraform apply` cluster-admin, so your
    # kubectl works immediately. Without this you get "error: You must be
    # logged in to the server" and no obvious way in.
    bootstrap_cluster_creator_admin_permissions = true
  }
}

# ---------------------------------------------------------------------------
# Worker nodes
#
# 2 x t3.small = 4 vCPU, inside the 5 vCPU account quota.
# Note the pod ceiling: t3.small supports 8 pods per node (an ENI limit, not
# a memory one), so ~16 pods cluster-wide minus system pods.
# ---------------------------------------------------------------------------

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-ng"
  node_role_arn   = data.aws_iam_role.node.arn
  subnet_ids      = aws_subnet.public[*].id
  instance_types  = [var.instance_type]

  scaling_config {
    desired_size = var.node_count
    min_size     = var.node_count
    max_size     = var.node_count
  }

  # Replace one node at a time so the cluster stays usable during upgrades.
  update_config {
    max_unavailable = 1
  }

  # Nodes can't register until the route to the internet exists.
  depends_on = [aws_route_table_association.public]
}

# ---------------------------------------------------------------------------
# Add-ons
#
# CoreDNS must come after the node group: it needs somewhere to schedule.
# ---------------------------------------------------------------------------

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"
  depends_on   = [aws_eks_node_group.main]
}
