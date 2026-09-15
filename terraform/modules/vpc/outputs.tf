output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets, for the EKS module to place nodes in."
  value       = aws_subnet.public[*].id
}

# The EKS node group depends on this so nodes can't launch before they have
# a route to the internet. Exposed as an output so the dependency survives
# the module boundary.
output "route_table_association_ids" {
  description = "Route table association IDs, used to order node group creation."
  value       = aws_route_table_association.public[*].id
}
