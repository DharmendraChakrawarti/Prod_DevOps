aws_region          = "ap-south-1"
project_name        = "dcmusic"
environment         = "dev"
cluster_name        = "dcmusic-eks"
kubernetes_version  = "1.31"
node_instance_types = ["t3.small"]   # t2.micro too small for EKS
node_desired_size   = 2
node_min_size       = 1
node_max_size       = 3
db_instance_class   = "db.t3.micro"  # Free Tier
db_name             = "dcmusic_db"
db_username         = "admin"
# db_password is provided securely via Jenkins credential (TF_VAR_db_password)
# For local runs: export TF_VAR_db_password="YourPassword"
# db_password         = "YourSecurePassword123!"