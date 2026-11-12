# =============================================================
#  ROOT OUTPUTS — Important values printed after terraform apply
# =============================================================

# -------------------------------------------------------
# VPC
# -------------------------------------------------------
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

# -------------------------------------------------------
# EKS Cluster
# -------------------------------------------------------
output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_certificate_authority" {
  description = "Base64 encoded certificate authority for the EKS cluster"
  value       = module.eks.cluster_certificate_authority
  sensitive   = true
}

output "eks_cluster_version" {
  description = "Kubernetes version running on the EKS cluster"
  value       = module.eks.cluster_version
}

output "eks_node_group_role_arn" {
  description = "ARN of the IAM role used by EKS worker nodes"
  value       = module.iam.eks_nodes_role_arn
}

output "eks_lb_controller_role_arn" {
  description = "ARN of the IAM role for AWS Load Balancer Controller (use with IRSA)"
  value       = module.eks.lb_controller_role_arn
}

output "eks_oidc_provider_arn" {
  description = "ARN of the OIDC provider for IRSA"
  value       = module.eks.oidc_provider_arn
}

output "kubeconfig_update_command" {
  description = "Run this command to configure kubectl to access the EKS cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

# -------------------------------------------------------
# RDS
# -------------------------------------------------------
output "rds_endpoint" {
  description = "RDS MySQL endpoint (hostname:port)"
  value       = module.rds.rds_endpoint
}

# -------------------------------------------------------
# ECR
# -------------------------------------------------------
output "ecr_backend_url" {
  description = "ECR repository URL for backend image"
  value       = module.ecr.backend_repository_url
}

output "ecr_frontend_url" {
  description = "ECR repository URL for frontend image"
  value       = module.ecr.frontend_repository_url
}
