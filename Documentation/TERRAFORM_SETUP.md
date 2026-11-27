# Terraform — DCMusic AWS Infrastructure

Complete Infrastructure-as-Code setup for the **DCMusic** application on AWS.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Project Structure](#project-structure)
- [Jenkins Pipelines](#jenkins-pipelines)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Module Reference](#module-reference)
- [Remote State Setup](#remote-state-setup)
- [Configuration](#configuration)
- [Common Operations](#common-operations)
- [Cost Breakdown](#cost-breakdown)
- [Troubleshooting](#troubleshooting)

---

## Architecture Overview

```
                        ┌─────────────────────────────────────────────────────┐
                        │                VPC  10.0.0.0/16                     │
                        │                                                     │
  Internet              │   Public Subnets            Private Subnets         │
     │                  │  ┌──────────────────┐    ┌──────────────────────┐   │
     │   ┌────────┐     │  │ 10.0.1.0/24 (AZ-a)│    │ 10.0.10.0/24 (AZ-a) │   │
     ├──▶│  IGW   │────▶│  │ 10.0.2.0/24 (AZ-b)│    │ 10.0.11.0/24 (AZ-b) │   │
     │   └────────┘     │  │                  │    │                      │   │
     │                  │  │  NAT Gateway     │    │  EKS Node Group      │   │
     │                  │  │  (outbound for   │───▶│  (2× t3.small)       │   │
     │                  │  │   private subs)  │    │                      │   │
     │                  │  │                  │    │  RDS MySQL 8.0       │   │
     │                  │  │  ALB (via LB     │    │  (db.t3.micro)       │   │
     │                  │  │   Controller)    │    │                      │   │
     │                  │  └──────────────────┘    └──────────────────────┘   │
     │                  │                                                     │
     │                  │   EKS Cluster (K8s 1.35)                           │
     │                  │   ECR: dcmusic-backend / dcmusic-frontend           │
     │                  └─────────────────────────────────────────────────────┘
     │
     │   ┌──────────────────────────────────────────┐
     └──▶│  S3 (TF State — Versioned + Encrypted)     │   ← Remote State
          └──────────────────────────────────────────┘
```

**Deployment order** (resolved automatically by Terraform's dependency graph):

1. **VPC** → Network foundation
2. **Security** → Security groups (needs VPC)
3. **ECR** → Docker image repos (independent)
4. **IAM** → EKS cluster + node IAM roles (independent)
5. **EKS** → Cluster, nodes, add-ons, OIDC, LB role (needs VPC, Security, IAM)
6. **RDS** → MySQL database (needs VPC, Security)

---

## Project Structure

```
terraform/
├── main.tf                      # Root module — wires all modules together
├── variables.tf                 # All configurable input variables
├── outputs.tf                   # Values printed after apply
├── provider.tf                  # AWS provider + backend config
├── terraform.tfvars             # Variable values (⚠️ gitignored)
├── terraform.tfvars.example     # Example tfvars (committed to git)
├── .gitignore
│
├── modules/
│   ├── vpc/                     # VPC, subnets, IGW, NAT, route tables
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── security/                # Security groups (EKS, RDS, legacy EC2)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── ecr/                     # ECR repos (backend + frontend)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── iam/                     # IAM roles for EKS cluster + nodes
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── eks/                     # EKS cluster, node group, add-ons, OIDC, LB role
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── rds/                     # RDS MySQL instance
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── ec2/                     # Legacy EC2 module (not used, kept for reference)
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── user_data.sh
│
├── remote-state/                # Bootstrap module for S3 backend
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
│
├── setup-remote-state.sh        # Shell script to create backend via AWS CLI

# Jenkins Pipelines (project root)
Jenkinsfile                      # App CI/CD — build, scan, push, deploy to EKS
Jenkinsfile.infra                # Infra provision — creates all AWS resources
Jenkinsfile.infra.delete         # Infra teardown — destroys all AWS resources
```

---

## Prerequisites

| Tool | Minimum Version | Check Command |
|------|----------------|---------------|
| Terraform | >= 1.5.0 | `terraform version` |
| AWS CLI | v2 | `aws --version` |
| kubectl | Match K8s version | `kubectl version --client` |

**AWS credentials** must be configured:
```bash
aws configure
# Or export environment variables:
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_DEFAULT_REGION="ap-south-1"
```

Verify access:
```bash
aws sts get-caller-identity
```

---

## Quick Start

### Step 1 — Clone and configure variables

```bash
cd /home/dc/Desktop/Prod_DevOps/terraform

# Create your tfvars from the example (if not already present)
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars — at minimum, change the DB password!
```

> ⚠️ **Never commit `terraform.tfvars`** — it's gitignored and contains your DB password.

### Step 2 — Create remote state backend & initialize Terraform

```bash
# Create S3 bucket (one-time, idempotent)
chmod +x setup-remote-state.sh
./setup-remote-state.sh

# Initialize Terraform with the S3 backend
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

terraform init \
  -backend-config="bucket=dcmusic-tf-state-${ACCOUNT_ID}" \
  -backend-config="key=dev/terraform.tfstate" \
  -backend-config="region=ap-south-1" \
  -backend-config="use_lockfile=true" \
  -backend-config="encrypt=true"
```

### Step 3 — Preview the plan

```bash
terraform plan
```

Review the output — it will show all resources to be created.

### Step 4 — Apply

```bash
terraform apply
```

Type `yes` when prompted. Full deployment takes **15–25 minutes** (EKS cluster alone takes ~10 min).

### Step 5 — Connect to EKS

After `apply` completes, run the printed `kubeconfig_update_command`:

```bash
aws eks update-kubeconfig --region ap-south-1 --name dcmusic-eks
```

Verify:
```bash
kubectl get nodes
kubectl get pods -A
```

---

## Jenkins Pipelines

Three Jenkins pipelines manage the full infrastructure lifecycle:

### Pipeline Overview

| Pipeline | File | Purpose |
|----------|------|---------|
| **Infra Provision** | `Jenkinsfile.infra` | Creates/updates all AWS infrastructure |
| **Infra Destroy** | `Jenkinsfile.infra.delete` | Tears down all AWS infrastructure |
| **App Deploy** | `Jenkinsfile` | Builds, scans, and deploys the application to EKS |

### Jenkins Credentials Required

| Credential ID | Type | Description |
|---------------|------|-------------|
| `aws-credentials` | AWS Credentials | AWS Access Key + Secret Access Key |
| `rds-password` | Secret text | RDS master password |

### Jenkinsfile.infra — Provision Pipeline (8 stages)

```
Checkout → Setup Remote State → Init (S3) → Validate → Plan → Approval (30m) → Apply → Kubeconfig
```

| Stage | What it does |
|-------|-------------|
| **Setup Remote State** | Auto-creates S3 bucket (idempotent — skips if exists). Locking uses native S3 lockfile. |
| **Terraform Init** | Initializes with dynamic `-backend-config` flags (no hardcoded account IDs) |
| **Terraform Validate** | Catches syntax errors early |
| **Terraform Plan** | Generates plan; DB password passed via `TF_VAR_db_password` env var (not `-var` flag) |
| **Manual Approval** | 30-minute timeout; prevents accidental infra changes |
| **Terraform Apply** | Applies the saved plan file |
| **Update Kubeconfig** | Configures kubectl on Jenkins agent + prints command for local dev |

**Setup in Jenkins:**
1. Create a new **Pipeline** job
2. Set **Pipeline script from SCM** → Git → your repo URL
3. Set **Script Path** to `Jenkinsfile.infra`
4. Run the pipeline

### Jenkinsfile.infra.delete — Destroy Pipeline (5 stages)

```
Checkout → Init (S3) → Plan Destroy → Approval (type cluster name) → Destroy
```

| Stage | What it does |
|-------|-------------|
| **Terraform Init** | Connects to existing S3 remote state |
| **Plan Destroy** | Shows exactly what will be deleted + counts resources |
| **Manual Approval** | Must type `dcmusic-eks` to confirm — prevents accidental destruction |
| **Terraform Destroy** | Applies the destroy plan — permanently deletes all resources |

> ⚠️ **This deletes EVERYTHING**: EKS cluster, RDS database (all data), VPC, ECR repos, IAM roles. The S3 state bucket is intentionally preserved for audit history.

**Setup in Jenkins:**
1. Create a new **Pipeline** job (e.g., `dcmusic-infra-destroy`)
2. Set **Script Path** to `Jenkinsfile.infra.delete`
3. **Restrict who can run this** — only admins should have access

### Jenkinsfile — Application Deployment Pipeline (10 stages)

```
Checkout → AWS Setup → Tests → Build → Docker Build → Security Scan → Push ECR → Update Manifests → Deploy EKS → Verify
```

This pipeline handles CI/CD for the application code (not infrastructure). It builds Docker images, scans for vulnerabilities with Trivy, pushes to ECR, and deploys to the EKS cluster via Helm.

---

## Module Reference

### 1. VPC Module (`modules/vpc/`)

Creates the network foundation with EKS-compatible subnet tags.

| Resource | Details |
|----------|---------|
| VPC | `10.0.0.0/16`, DNS support + hostnames enabled |
| Public Subnets | `10.0.1.0/24` (AZ-a), `10.0.2.0/24` (AZ-b) — tagged for external ELB |
| Private Subnets | `10.0.10.0/24` (AZ-a), `10.0.11.0/24` (AZ-b) — tagged for internal ELB |
| Internet Gateway | Routes public subnet traffic to internet |
| NAT Gateway | Single NAT in first public subnet (cost-optimized) |
| Route Tables | Public → IGW, Private → NAT |

### 2. Security Module (`modules/security/`)

| Security Group | Purpose | Key Rules |
|---------------|---------|-----------|
| EKS Cluster SG | API server access | Inbound 443 from VPC CIDR + node SG |
| EKS Nodes SG | Worker node traffic | All from cluster SG, self (node-to-node), kubelet 10250, NodePort 30000–32767 |
| RDS SG | Database access | Inbound 3306 from EKS nodes SG |
| EC2 SG | Legacy | SSH 22, HTTP 80, ports 3000/8080 (not actively used) |

### 3. ECR Module (`modules/ecr/`)

| Repository | Image |
|-----------|-------|
| `dcmusic-backend` | Spring Boot application |
| `dcmusic-frontend` | React app served by Nginx |

Both have `force_delete = true` and mutable tags (allows `:latest` overwrites).

### 4. IAM Module (`modules/iam/`)

| Role | Attached Policies |
|------|-------------------|
| EKS Cluster Role | `AmazonEKSClusterPolicy` |
| EKS Node Role | `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`, `AmazonSSMManagedInstanceCore` |

### 5. EKS Module (`modules/eks/`)

| Component | Configuration |
|-----------|--------------|
| Cluster | K8s 1.35, public + private API access, CloudWatch logs (api, audit, authenticator) |
| Access Config | `API_AND_CONFIG_MAP` authentication mode with `bootstrap_cluster_creator_admin_permissions = true` |
| Node Group | 2× t3.small (min 1, max 3), ON_DEMAND, 20 GB disk, Amazon Linux 2023 (AL2023), private subnets |
| Add-ons | VPC CNI, CoreDNS, kube-proxy |
| OIDC Provider | Enables IRSA (IAM Roles for Service Accounts) |
| LB Controller Role | IRSA role for `aws-load-balancer-controller` in `kube-system` |

### 6. RDS Module (`modules/rds/`)

| Setting | Value |
|---------|-------|
| Engine | MySQL 8.0 |
| Instance | db.t3.micro (Free Tier) |
| Storage | 20 GB gp2, encrypted (AES-256) |
| Network | Private subnets only, not publicly accessible |
| Backups | 1-day retention (AWS Free Tier limit) |
| Multi-AZ | Disabled (dev) |
| Deletion Protection | Disabled (dev) |

---

## Remote State Setup

Terraform state is stored in **S3** with **native S3 locking** (`use_lockfile = true`). The backend uses a partial configuration (`backend "s3" {}` in `provider.tf`) — actual values are passed at `terraform init` time.

> **Jenkins handles this automatically.** The `Jenkinsfile.infra` pipeline creates the S3 bucket in its "Setup Remote State" stage, then passes the config to `terraform init`. You only need the manual steps below for local development.

### Option A — Shell Script (Recommended for local dev)

```bash
cd /home/dc/Desktop/Prod_DevOps/terraform

chmod +x setup-remote-state.sh
./setup-remote-state.sh
```

This creates:
- S3 bucket: `dcmusic-tf-state-<ACCOUNT_ID>` (versioned, encrypted, private)

Locking is handled natively by S3 (`use_lockfile = true`) — no DynamoDB needed.

### Option B — Terraform Module

```bash
cd /home/dc/Desktop/Prod_DevOps/terraform/remote-state

terraform init
terraform plan
terraform apply
```

### After creating backend resources — Migrate state

**1. Uncomment** the S3 backend in `provider.tf`:

```hcl
backend "s3" {
  bucket       = "dcmusic-tf-state-<YOUR_ACCOUNT_ID>"
  key          = "dev/terraform.tfstate"
  region       = "ap-south-1"
  use_lockfile = true
  encrypt      = true
}
```

**2. Initialize with migration:**

```bash
cd /home/dc/Desktop/Prod_DevOps/terraform
terraform init
# When prompted "Do you want to copy existing state?" → yes
```

**3. Verify:**

```bash
terraform state list
```

**4. Clean up local state files:**

```bash
rm -f terraform.tfstate terraform.tfstate.backup
```

### Dynamic Backend Config (Alternative)

Avoid hardcoding the bucket name — use an empty backend block:

```hcl
backend "s3" {}
```

Then init with flags:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

terraform init \
  -backend-config="bucket=dcmusic-tf-state-${ACCOUNT_ID}" \
  -backend-config="key=dev/terraform.tfstate" \
  -backend-config="region=ap-south-1" \
  -backend-config="use_lockfile=true" \
  -backend-config="encrypt=true"
```

---

## Configuration

All variables are defined in `variables.tf` with sensible defaults. Override them in `terraform.tfvars`:

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `ap-south-1` | AWS region |
| `project_name` | `dcmusic` | Prefix for all resource names |
| `environment` | `dev` | Environment tag (dev/staging/prod) |
| `vpc_cidr` | `10.0.0.0/16` | VPC CIDR block |
| `cluster_name` | `dcmusic-eks` | EKS cluster name |
| `kubernetes_version` | `1.35` | K8s version |
| `node_instance_types` | `["t3.small"]` | EC2 types for EKS nodes |
| `node_desired_size` | `2` | Desired node count |
| `node_min_size` / `node_max_size` | `1` / `3` | Autoscaling bounds |
| `db_instance_class` | `db.t3.micro` | RDS instance size |
| `db_name` | `dcmusic_db` | MySQL database name |
| `db_username` | `admin` | RDS master username |
| `db_password` | *(none)* | RDS password (**use env var!**) |

### Secure password handling

Instead of putting the password in `terraform.tfvars`, use an environment variable:

```bash
export TF_VAR_db_password="YourSecurePassword123!"
terraform plan
terraform apply
```

---

## Common Operations

### View all deployed resources
```bash
terraform state list
```

### Update infrastructure after changing variables
```bash
terraform plan      # preview changes
terraform apply     # apply changes
```

### Destroy everything (dev teardown)
```bash
terraform destroy
```

> ⚠️ This deletes ALL resources including the RDS database. EKS cluster deletion takes ~10 minutes.

### Import an existing resource into state
```bash
terraform import module.vpc.aws_vpc.main vpc-0abc123def456
```

### Refresh state to match real infrastructure
```bash
terraform refresh
```

### Format all `.tf` files
```bash
terraform fmt -recursive
```

### Validate configuration
```bash
terraform validate
```

### Show specific resource details
```bash
terraform state show module.eks.aws_eks_cluster.main
```

### Unlock a stuck state lock
```bash
terraform force-unlock <LOCK_ID>
```

---

## Cost Breakdown (dev environment, ap-south-1)

| Resource | Monthly Cost |
|----------|-------------|
| EKS Control Plane | ~$73 |
| 2× t3.small nodes | ~$33 |
| NAT Gateway + data | ~$32 |
| RDS db.t3.micro | Free Tier eligible |
| ECR (storage) | Negligible |
| S3 (state) | < $1 |
| **Total** | **~$138/mo** |

### Cost-saving tips

- **Destroy when not in use:** `terraform destroy` saves the full ~$138/mo
- **Scale nodes to 1:** Set `node_desired_size = 1` in tfvars (~$16/mo saved)
- **NAT Gateway alternative:** For dev, consider a NAT instance (t3.micro) instead (~$28/mo saved)

---

## Troubleshooting

### `Error: creating S3 Bucket: AccessDenied`
Verify your IAM user or role has `s3:CreateBucket`, `s3:PutBucketVersioning`, `s3:PutEncryptionConfiguration`, and `s3:PutBucketPublicAccessBlock` permissions in the selected region.

### `Error: creating EKS Cluster: InvalidParameterException: unsupported Kubernetes version`
Check available versions: `aws eks describe-addon-versions --region ap-south-1 | grep -o '"1\.[0-9]*"' | sort -u`

### `Error: creating EKS Node Group: instances failed to join the cluster`
Common causes:
- Node IAM role missing required policies
- Private subnets can't reach the internet (NAT Gateway issue)
- Node security group missing cluster API access

### `terraform init` fails with backend error
If migrating from local → S3 and it fails, you can force reconfigure:
```bash
terraform init -reconfigure
```

### State lock stuck / `Error: Error locking state`
If a previous `apply` crashed and left the state lock:
```bash
# The error message contains the Lock ID
terraform force-unlock <LOCK_ID_FROM_ERROR>
```

### EKS nodes `NotReady`
Wait 2–3 minutes after apply. If still not ready:
```bash
kubectl describe nodes
# Check for CNI or kubelet issues in the events
```

---

## Outputs

After `terraform apply`, these values are printed:

| Output | Description |
|--------|-------------|
| `vpc_id` | VPC ID |
| `eks_cluster_name` | EKS cluster name |
| `eks_cluster_endpoint` | API server URL |
| `eks_cluster_version` | Running K8s version |
| `eks_lb_controller_role_arn` | IAM role ARN for ALB Controller (use in Helm chart) |
| `eks_oidc_provider_arn` | OIDC provider ARN for IRSA |
| `kubeconfig_update_command` | Copy-paste command to configure kubectl |
| `rds_endpoint` | RDS MySQL connection string (hostname:port) |
| `ecr_backend_url` | ECR URL for backend Docker image |
| `ecr_frontend_url` | ECR URL for frontend Docker image |

Re-print outputs anytime:
```bash
terraform output
terraform output rds_endpoint
```
