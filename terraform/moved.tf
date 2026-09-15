# State refactoring, declared rather than performed by hand.
#
# Moving a resource into a module changes its address in state
# (aws_vpc.main becomes module.vpc.aws_vpc.main). Without these blocks
# Terraform reads that as "the old resource is gone, a new one is wanted"
# and plans a destroy + create — which would delete your live cluster.
#
# `moved` blocks tell Terraform the resource is the same thing under a new
# address. No `terraform state mv` required, and the refactor is reviewable
# in a pull request like any other change.
#
# Correctness check: after adding these, `terraform plan` must report
# "No changes." Anything else means an address is wrong — fix it before applying.
#
# These can be deleted once the refactor has been applied everywhere,
# but they are harmless to keep.

moved {
  from = aws_vpc.main
  to   = module.vpc.aws_vpc.main
}

moved {
  from = aws_internet_gateway.main
  to   = module.vpc.aws_internet_gateway.main
}

moved {
  from = aws_subnet.public
  to   = module.vpc.aws_subnet.public
}

moved {
  from = aws_route_table.public
  to   = module.vpc.aws_route_table.public
}

moved {
  from = aws_route_table_association.public
  to   = module.vpc.aws_route_table_association.public
}

moved {
  from = aws_eks_cluster.main
  to   = module.eks.aws_eks_cluster.main
}

moved {
  from = aws_eks_node_group.main
  to   = module.eks.aws_eks_node_group.main
}

moved {
  from = aws_eks_addon.vpc_cni
  to   = module.eks.aws_eks_addon.vpc_cni
}

moved {
  from = aws_eks_addon.kube_proxy
  to   = module.eks.aws_eks_addon.kube_proxy
}

moved {
  from = aws_eks_addon.coredns
  to   = module.eks.aws_eks_addon.coredns
}

moved {
  from = aws_ecr_repository.app
  to   = module.ecr.aws_ecr_repository.app
}

moved {
  from = aws_ecr_lifecycle_policy.app
  to   = module.ecr.aws_ecr_lifecycle_policy.app
}
