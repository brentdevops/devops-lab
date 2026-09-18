output "alb_dns_name" {
  description = "Hit this in a browser. This is what you hand back on the ticket."
  value       = aws_lb.main.dns_name
}

output "instance_id" {
  description = "For: aws ssm start-session --target <id>"
  value       = aws_instance.app.id
}

output "nat_public_ip" {
  description = "Every outbound request from the private subnet appears as this IP."
  value       = aws_eip.nat.public_ip
}

output "target_group_arn" {
  description = "For: aws elbv2 describe-target-health --target-group-arn <arn>"
  value       = aws_lb_target_group.app.arn
}
