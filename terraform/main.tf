# =============================================================
#  ROOT MAIN — Wires all modules together
# =============================================================
#  Deployment order (resolved by Terraform dependency graph):
#    1. VPC        (network foundation)
#    2. Security   (security groups — needs VPC)
#    3. ECR        (independent — Docker repos)
#    4. IAM        (EKS cluster + node IAM roles — independent)
#    5. EKS        (cluster + nodes + addons + OIDC + LB role)
#    6. RDS        (MySQL — needs VPC + Security)
# =============================================================

# -----------------------------------------------------------
# 1. VPC MODULE — Network foundation
# -----------------------------------------------------------
module "vpc" {
  source = "./modules/vpc"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  cluster_name         = var.cluster_name
}

# -----------------------------------------------------------
# 2. SECURITY MODULE — Security Groups
# -----------------------------------------------------------
module "security" {
  source = "./modules/security"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = module.vpc.vpc_cidr_block
}

# -----------------------------------------------------------
# 3. ECR MODULE — Docker image repositories (unchanged)
# -----------------------------------------------------------
module "ecr" {
  source = "./modules/ecr"

  project_name = var.project_name
  environment  = var.environment
}

# -----------------------------------------------------------
# 4. IAM MODULE — EKS base IAM roles (cluster + node)
#    These have no dependency on EKS outputs, so they're
#    created first and fed into the EKS module.
# -----------------------------------------------------------
module "iam" {
  source = "./modules/iam"

  project_name = var.project_name
  environment  = var.environment
}

# -----------------------------------------------------------
# 5. EKS MODULE — Cluster, nodes, add-ons, OIDC, LB controller
#    NOTE: EKS control plane costs ~$0.10/hr (~$73/mo).
#          This is NOT AWS Free Tier.
# -----------------------------------------------------------
module "eks" {
  source = "./modules/eks"

  project_name  = var.project_name
  environment   = var.environment
  cluster_name  = var.cluster_name

  kubernetes_version = var.kubernetes_version

  # IAM roles from iam module
  cluster_role_arn = module.iam.eks_cluster_role_arn
  node_role_arn    = module.iam.eks_nodes_role_arn

  # Networking
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  # Security Groups
  cluster_security_group_id = module.security.eks_cluster_security_group_id
  node_security_group_id    = module.security.eks_nodes_security_group_id

  # Node Group sizing
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_disk_size      = var.node_disk_size

  # Ensure IAM policy attachments and VPC networking (NAT gateway) are fully ready
  depends_on = [
    module.iam,
    module.vpc
  ]
}

# -----------------------------------------------------------
# 6. RDS MODULE — MySQL database (Free Tier: db.t3.micro)
# -----------------------------------------------------------
module "rds" {
  source = "./modules/rds"

  project_name      = var.project_name
  environment       = var.environment
  db_instance_class = var.db_instance_class
  db_name           = var.db_name
  db_username       = var.db_username
  db_password       = var.db_password
  subnet_ids        = module.vpc.private_subnet_ids
  security_group_id = module.security.rds_security_group_id
}

# -----------------------------------------------------------
# 7. EC2 MODULE — COMMENTED OUT (kept for reference)
#    EC2 is replaced by EKS for application workloads.
#    The module files in modules/ec2/ are preserved as reference.
# -----------------------------------------------------------
# module "ec2" {
#   source = "./modules/ec2"
#
#   project_name      = var.project_name
#   environment       = var.environment
#   instance_type     = var.ec2_instance_type
#   key_name          = var.ec2_key_name
#   subnet_id         = module.vpc.public_subnet_ids[0]
#   security_group_id = module.security.ec2_security_group_id
#   ecr_backend_url   = module.ecr.backend_repository_url
#   ecr_frontend_url  = module.ecr.frontend_repository_url
#   rds_endpoint      = module.rds.rds_endpoint
#   rds_db_name       = var.db_name
#   rds_username      = var.db_username
#   rds_password      = var.db_password
#   aws_region        = var.aws_region
# }
