# EKS Module — Input Variables

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.29"
}

variable "cluster_role_arn" {
  description = "IAM role ARN for the EKS cluster"
  type        = string
}

variable "node_role_arn" {
  description = "IAM role ARN for the EKS node group"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for EKS"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EKS nodes"
  type        = list(string)
}

variable "cluster_security_group_id" {
  description = "Security group ID for the EKS cluster"
  type        = string
}

variable "node_security_group_id" {
  description = "Security group ID for EKS worker nodes"
  type        = string
}

variable "node_instance_types" {
  description = "Instance types for the EKS node group"
  type        = list(string)
  default     = ["t3.small"]
}

variable "node_desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 3
}

variable "node_disk_size" {
  description = "Disk size in GB for each node"
  type        = number
  default     = 20
}

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
}
