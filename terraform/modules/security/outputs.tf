# Security Module — Outputs

output "ec2_security_group_id" {
  description = "Security Group ID for EC2 (legacy)"
  value       = aws_security_group.ec2.id
}

output "rds_security_group_id" {
  description = "Security Group ID for RDS"
  value       = aws_security_group.rds.id
}

output "eks_cluster_security_group_id" {
  description = "Security Group ID for EKS cluster"
  value       = aws_security_group.eks_cluster.id
}

output "eks_nodes_security_group_id" {
  description = "Security Group ID for EKS worker nodes"
  value       = aws_security_group.eks_nodes.id
}
