# =============================================================
#  ROOT VARIABLES — All configurable inputs for the infrastructure
# =============================================================

variable "aws_region" {
  description = "AWS Region to deploy resources"
  type        = string
  default     = "ap-south-1" # Mumbai
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "dcmusic"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

# -------------------------------------------------------
# VPC Configuration
# -------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (ALB / Load Balancers)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (EKS nodes + RDS)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "availability_zones" {
  description = "Availability zones to use (must have at least 2)"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

# -------------------------------------------------------
# EKS Configuration
# -------------------------------------------------------
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "dcmusic-eks"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.29"
}

variable "node_instance_types" {
  description = "EC2 instance types for EKS worker nodes (t3.small minimum for EKS)"
  type        = list(string)
  default     = ["t3.small"] # t2.micro is too small for EKS workloads
}

variable "node_desired_size" {
  description = "Desired number of EKS worker nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of EKS worker nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of EKS worker nodes"
  type        = number
  default     = 3
}

variable "node_disk_size" {
  description = "Disk size in GB for each EKS worker node"
  type        = number
  default     = 20
}

# -------------------------------------------------------
# EC2 Configuration (legacy — kept for reference)
# -------------------------------------------------------
variable "ec2_instance_type" {
  description = "EC2 instance type (legacy, not used with EKS)"
  type        = string
  default     = "t3.micro"
}

variable "ec2_key_name" {
  description = "Name of the SSH key pair (legacy, not used with EKS)"
  type        = string
  default     = ""
}

# -------------------------------------------------------
# RDS Configuration
# -------------------------------------------------------
variable "db_instance_class" {
  description = "RDS instance class (db.t3.micro = Free Tier)"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Name of the MySQL database"
  type        = string
  default     = "dcmusic_db"
}

variable "db_username" {
  description = "Master username for RDS"
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "Master password for RDS (use TF_VAR_db_password env or -var flag, never commit)"
  type        = string
  sensitive   = true
}

variable "backup_retention_period" {
  description = "The days to retain backups for RDS (Free Tier max is 1 day)"
  type        = number
  default     = 1
}
