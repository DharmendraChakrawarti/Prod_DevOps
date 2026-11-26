# 🎵 DC Music — Complete Project Implementation Guide

> Step-by-step guide to deploy DC Music on AWS EKS with Jenkins CI/CD, ArgoCD GitOps, Prometheus & Grafana monitoring — **optimized for AWS Free Tier, no DNS required**.

---

## Table of Contents

1. [Prerequisites & Tools Installation](#1-prerequisites--tools-installation)
2. [AWS Account Setup](#2-aws-account-setup)
3. [Spring Boot Backend Preparation](#3-spring-boot-backend-preparation)
4. [Local Development & Testing](#4-local-development--testing)
5. [Terraform — Provision AWS Infrastructure](#5-terraform--provision-aws-infrastructure)
6. [EKS Cluster Configuration](#6-eks-cluster-configuration)
7. [AWS Load Balancer Controller Setup](#7-aws-load-balancer-controller-setup)
8. [Docker Build & Push to ECR](#8-docker-build--push-to-ecr)
9. [Deploy Application to EKS](#9-deploy-application-to-eks)
10. [ArgoCD GitOps Setup](#10-argocd-gitops-setup)
11. [Prometheus & Grafana Monitoring](#11-prometheus--grafana-monitoring)
12. [Jenkins CI/CD Setup](#12-jenkins-cicd-setup)
13. [End-to-End Verification](#13-end-to-end-verification)
14. [Cost Management & Cleanup](#14-cost-management--cleanup)
15. [Troubleshooting](#15-troubleshooting)

---

## 1. Prerequisites & Tools Installation

> [!IMPORTANT]
> Install ALL of these tools on your local machine (or Jenkins server) BEFORE starting. Verify each with the version commands shown.

### 1.1 — Required Tools

| Tool | Minimum Version | Purpose | Install Command (Ubuntu/Debian) |
|------|----------------|---------|--------------------------------|
| **AWS CLI** | v2.x | AWS API access | See below |
| **Terraform** | >= 1.5.0 | Infrastructure as Code | See below |
| **kubectl** | v1.29+ | Kubernetes cluster management | See below |
| **Helm** | v3.x | Kubernetes package manager | See below |
| **Docker** | 20.x+ | Container builds | See below |
| **Git** | 2.x+ | Version control | `sudo apt install git` |
| **Java JDK** | 17 | Backend compilation | `sudo apt install openjdk-17-jdk` |
| **Maven** | 3.9+ | Java build tool | `sudo apt install maven` |
| **Node.js** | 20.x | Frontend build | See below |
| **Trivy** | Latest | Container security scanning | See below |

### 1.2 — Installation Commands

```bash
# ============================================================
# AWS CLI v2
# ============================================================
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version
# Expected: aws-cli/2.x.x

# ============================================================
# Terraform
# ============================================================
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
wget -O- https://apt.releases.hashicorp.com/gpg | \
  gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install terraform
terraform -version
# Expected: Terraform v1.5.0+

# ============================================================
# kubectl
# ============================================================
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client
# Expected: Client Version: v1.29+

# ============================================================
# Helm 3
# ============================================================
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
# Expected: version.BuildInfo{Version:"v3.x.x"}

# ============================================================
# Docker
# ============================================================
# If not installed, install Docker Engine:
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
# Log out and back in for group change to take effect
docker --version
# Expected: Docker version 24.x+

# ============================================================
# Node.js 20 (via nvm)
# ============================================================
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
source ~/.bashrc
nvm install 20
nvm use 20
node --version
# Expected: v20.x.x

# ============================================================
# Trivy (Container Security Scanner)
# ============================================================
sudo apt-get install wget apt-transport-https gnupg lsb-release
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor | \
  sudo tee /usr/share/keyrings/trivy.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb \
  $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/trivy.list
sudo apt-get update && sudo apt-get install trivy
trivy --version
# Expected: Version: 0.x.x

# ============================================================
# eksctl (optional but recommended)
# ============================================================
ARCH=amd64
PLATFORM=$(uname -s)_$ARCH
curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && sudo mv /tmp/eksctl /usr/local/bin
eksctl version
```

### 1.3 — Verify All Tools

```bash
echo "=== Tool Versions ==="
aws --version
terraform -version
kubectl version --client --short 2>/dev/null || kubectl version --client
helm version --short
docker --version
java -version
mvn -version
node --version
npm --version
trivy --version
echo "=== All OK ✅ ==="
```

---

## 2. AWS Account Setup

### 2.1 — Create IAM User

1. Login to **AWS Console** → **IAM** → **Users** → **Create User**
2. User name: `dcmusic-admin`
3. Select **"Attach policies directly"** and attach these policies:

| Policy Name | Purpose |
|---|---|
| `AmazonEKSClusterPolicy` | EKS cluster management |
| `AmazonEKSWorkerNodePolicy` | EKS node group management |
| `AmazonEKS_CNI_Policy` | VPC networking for pods |
| `AmazonEC2FullAccess` | EC2 instances, security groups, VPC |
| `AmazonVPCFullAccess` | VPC, subnets, NAT gateway |
| `AmazonS3FullAccess` | S3 for Terraform state |
| `AmazonRDSFullAccess` | RDS MySQL provisioning |
| `AmazonEC2ContainerRegistryFullAccess` | ECR push/pull |
| `AmazonDynamoDBFullAccess` | DynamoDB for Terraform state locking |
| `IAMFullAccess` | Create EKS roles, OIDC provider |
| `ElasticLoadBalancingFullAccess` | ALB for Ingress |
| `AmazonSSMReadOnlyAccess` | SSM for node management |
| `CloudWatchLogsFullAccess` | EKS control plane logging |

4. Under **"Security credentials"** tab → **Create access key** → Select **"CLI"**
5. **Save** the Access Key ID and Secret Access Key

### 2.2 — Configure AWS CLI

```bash
aws configure
# Enter:
#   AWS Access Key ID:     <YOUR_ACCESS_KEY_ID>
#   AWS Secret Access Key: <YOUR_SECRET_ACCESS_KEY>
#   Default region name:   ap-south-1
#   Default output format: json

# Verify:
aws sts get-caller-identity
# Should return your account ID, user ARN, and account number
```

> [!TIP]
> Save your AWS Account ID — you'll need it in several places:
> ```bash
> export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
> echo "Your AWS Account ID: $AWS_ACCOUNT_ID"
> ```

### 2.3 — Create Terraform Remote State Resources

Terraform needs an S3 bucket and DynamoDB table to store and lock its state:

```bash
# Get your account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create S3 bucket for Terraform state
aws s3 mb s3://dcmusic-tf-state-${AWS_ACCOUNT_ID} --region ap-south-1
echo "✅ S3 bucket created: dcmusic-tf-state-${AWS_ACCOUNT_ID}"

# Enable versioning (protects against accidental state corruption)
aws s3api put-bucket-versioning \
  --bucket dcmusic-tf-state-${AWS_ACCOUNT_ID} \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name dcmusic-tf-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-south-1
echo "✅ DynamoDB table created: dcmusic-tf-lock"
```

---

## 3. Spring Boot Backend Preparation

### 3.1 — Add Spring Boot Actuator Dependency

The backend needs Actuator for Kubernetes health probes and Prometheus metrics scraping. Add this to `backend/pom.xml` inside `<dependencies>`:

```xml
<!-- Spring Boot Actuator — health checks + Prometheus metrics -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>

<!-- Micrometer Prometheus registry — exposes /actuator/prometheus -->
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
    <scope>runtime</scope>
</dependency>
```

### 3.2 — EKS Profile Properties

The file `backend/src/main/resources/application-eks.properties` is already created with:

```properties
# Actuator endpoints for K8s probes & Prometheus
management.endpoints.web.exposure.include=health,info,prometheus,metrics
management.endpoint.health.show-details=always
management.endpoint.prometheus.enabled=true

# Graceful shutdown for zero-downtime rolling deployments
server.shutdown=graceful
spring.lifecycle.timeout-per-shutdown-phase=30s
```

> [!NOTE]
> This profile is activated by setting the environment variable `SPRING_PROFILES_ACTIVE=eks` in the Kubernetes deployment. The ConfigMap in `k8s/base/backend/configmap.yaml` already sets this.

---

## 4. Local Development & Testing

Before deploying to AWS, test locally to verify the app works:

```bash
cd /home/dc/Desktop/Prod_DevOps

# Start with Docker Compose (local H2 database, no AWS needed)
make dev-up
# OR: docker-compose up --build -d

# Verify:
# Frontend: http://localhost:5173
# Backend API: http://localhost:8080/api

# Check container status
docker-compose ps

# Check logs
docker-compose logs -f backend
docker-compose logs -f frontend

# Stop
make dev-down
# OR: docker-compose down
```

---

## 5. Terraform — Provision AWS Infrastructure

### 5.1 — What Terraform Creates

| Module | Resources | Estimated Cost |
|---|---|---|
| **vpc** | VPC, 2 public subnets, 2 private subnets, IGW, NAT Gateway, route tables | \$32/mo (NAT GW) |
| **iam** | EKS Cluster IAM role, Node Group IAM role | Free |
| **eks** | EKS cluster (v1.29), managed node group (2× t3.small), add-ons, OIDC provider, LB controller role | \$73/mo (control plane) + \$33/mo (nodes) |
| **ecr** | 2 ECR repositories (backend + frontend) | ~\$0 |
| **rds** | MySQL 8.0 (db.t3.micro), encrypted, 7-day backups | Free (12 months) |
| **security** | EKS cluster SG, node SG, RDS SG | Free |

> [!WARNING]
> **EKS control plane costs ~\$73/month** — this is NOT covered by Free Tier. The total infrastructure costs ~\$138-160/month. Run `terraform destroy` when not actively using the cluster to avoid charges.

### 5.2 — Configure Variables

```bash
cd /home/dc/Desktop/Prod_DevOps/terraform

# Copy example variables and customize
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars — at minimum, change the database password:
nano terraform.tfvars
```

Key values in `terraform.tfvars`:
```hcl
aws_region          = "ap-south-1"
project_name        = "dcmusic"
environment         = "dev"
cluster_name        = "dcmusic-eks"
kubernetes_version  = "1.29"
node_instance_types = ["t3.small"]   # t2.micro too small for EKS
node_desired_size   = 2
node_min_size       = 1
node_max_size       = 3
db_instance_class   = "db.t3.micro"  # Free Tier
db_name             = "dcmusic_db"
db_username         = "admin"
db_password         = "YourSecurePassword123!"  # ⚠️ CHANGE THIS!
```

### 5.3 — Initialize & Apply

```bash
cd /home/dc/Desktop/Prod_DevOps/terraform

# Step 1: Initialize Terraform (downloads providers, configures S3 backend)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

terraform init \
  -backend-config="bucket=dcmusic-tf-state-${AWS_ACCOUNT_ID}" \
  -backend-config="key=dev/terraform.tfstate" \
  -backend-config="region=ap-south-1" \
  -backend-config="dynamodb_table=dcmusic-tf-lock" \
  -backend-config="encrypt=true"

# Step 2: Preview what will be created
terraform plan -out=tfplan

# Step 3: Apply (creates ALL resources — takes 15-20 minutes)
terraform apply tfplan
```

### 5.4 — Expected Output After Apply

```
Apply complete! Resources: ~30 added, 0 changed, 0 destroyed.

Outputs:
  eks_cluster_name             = "dcmusic-eks"
  eks_cluster_endpoint         = "https://XXXXX.gr7.ap-south-1.eks.amazonaws.com"
  eks_lb_controller_role_arn   = "arn:aws:iam::XXXX:role/dcmusic-dev-lb-controller-role"
  kubeconfig_update_command    = "aws eks update-kubeconfig --region ap-south-1 --name dcmusic-eks"
  rds_endpoint                 = "dcmusic-dev-mysql.xxxxx.ap-south-1.rds.amazonaws.com:3306"
  ecr_backend_url              = "XXXX.dkr.ecr.ap-south-1.amazonaws.com/dcmusic-backend"
  ecr_frontend_url             = "XXXX.dkr.ecr.ap-south-1.amazonaws.com/dcmusic-frontend"
```

> [!IMPORTANT]
> **Save these outputs!** You'll need `rds_endpoint`, `ecr_backend_url`, `ecr_frontend_url`, and `eks_lb_controller_role_arn` in the next steps.
> ```bash
> # Save outputs to a file for reference
> terraform output > ../terraform-outputs.txt
> ```

---

## 6. EKS Cluster Configuration

### 6.1 — Configure kubectl

```bash
# Update kubeconfig to connect to the EKS cluster
aws eks update-kubeconfig --name dcmusic-eks --region ap-south-1

# Verify connection
kubectl get nodes
# Expected output (2 nodes, STATUS: Ready):
# NAME                                          STATUS   ROLES    AGE   VERSION
# ip-10-0-10-xx.ap-south-1.compute.internal     Ready    <none>   5m    v1.29.x
# ip-10-0-11-xx.ap-south-1.compute.internal     Ready    <none>   5m    v1.29.x

# Check system pods
kubectl get pods -n kube-system
# You should see coredns, kube-proxy, aws-node (vpc-cni) running

# Cluster info
kubectl cluster-info
```

### 6.2 — Verify EKS Add-ons

```bash
# Check add-ons
aws eks list-addons --cluster-name dcmusic-eks --region ap-south-1
# Expected: ["coredns", "kube-proxy", "vpc-cni"]

# Verify all system pods are running
kubectl get pods -n kube-system -o wide
```

---

## 7. AWS Load Balancer Controller Setup

The ALB controller creates AWS Application Load Balancers from Kubernetes Ingress resources. This is how your app gets exposed to the internet **without needing Route53/DNS**.

### 7.1 — Install cert-manager (dependency)

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml

# Wait for cert-manager to be ready
kubectl wait --for=condition=available deployment/cert-manager -n cert-manager --timeout=120s
kubectl wait --for=condition=available deployment/cert-manager-webhook -n cert-manager --timeout=120s
```

### 7.2 — Install AWS Load Balancer Controller

```bash
# Add EKS Helm chart repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Get the LB controller role ARN from Terraform output
LB_ROLE_ARN=$(cd /home/dc/Desktop/Prod_DevOps/terraform && terraform output -raw eks_lb_controller_role_arn)
echo "LB Controller Role ARN: $LB_ROLE_ARN"

# Install the controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=dcmusic-eks \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$LB_ROLE_ARN" \
  --set region=ap-south-1 \
  --set vpcId=$(cd /home/dc/Desktop/Prod_DevOps/terraform && terraform output -raw vpc_id)

# Verify it's running
kubectl get deployment aws-load-balancer-controller -n kube-system
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

---

## 8. Docker Build & Push to ECR

### 8.1 — Login to ECR

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=ap-south-1

aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin \
  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

echo "✅ ECR login successful"
```

### 8.2 — Build & Push Backend Image

```bash
cd /home/dc/Desktop/Prod_DevOps

# Build the backend Docker image
docker build -t ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/dcmusic-backend:v1 \
  -t ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/dcmusic-backend:latest \
  ./backend

# Push to ECR
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/dcmusic-backend:v1
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/dcmusic-backend:latest

echo "✅ Backend image pushed to ECR"
```

### 8.3 — Build & Push Frontend Image

```bash
# Build the frontend Docker image
docker build -t ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/dcmusic-frontend:v1 \
  -t ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/dcmusic-frontend:latest \
  ./frontend

# Push to ECR
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/dcmusic-frontend:v1
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/dcmusic-frontend:latest

echo "✅ Frontend image pushed to ECR"
```

### 8.4 — Verify Images in ECR

```bash
aws ecr list-images --repository-name dcmusic-backend --region $AWS_REGION
aws ecr list-images --repository-name dcmusic-frontend --region $AWS_REGION
```

---

## 9. Deploy Application to EKS

You have **3 deployment options**. Choose ONE:

### Option A: Raw Kubernetes Manifests (Simplest)

```bash
cd /home/dc/Desktop/Prod_DevOps

# Step 1: Create the namespace
kubectl apply -f k8s/base/namespace.yaml

# Step 2: Create database secret (REPLACE values with YOUR RDS endpoint & password)
RDS_ENDPOINT=$(cd terraform && terraform output -raw rds_endpoint)

kubectl create secret generic dcmusic-db-secret \
  --from-literal=SPRING_DATASOURCE_URL="jdbc:mysql://${RDS_ENDPOINT}/dcmusic_db?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC&createDatabaseIfNotExist=true" \
  --from-literal=SPRING_DATASOURCE_USERNAME="admin" \
  --from-literal=SPRING_DATASOURCE_PASSWORD="YourSecurePassword123!" \
  -n dcmusic

# Step 3: Update image URLs in manifests
# Edit k8s/base/backend/deployment.yaml and k8s/base/frontend/deployment.yaml
# Replace ACCOUNT_ID with your actual AWS Account ID in the image field

sed -i "s/ACCOUNT_ID/${AWS_ACCOUNT_ID}/g" k8s/base/backend/deployment.yaml
sed -i "s/ACCOUNT_ID/${AWS_ACCOUNT_ID}/g" k8s/base/frontend/deployment.yaml

# Step 4: Apply all manifests
kubectl apply -f k8s/base/ -R

# Step 5: Verify deployment
kubectl get all -n dcmusic
kubectl get ingress -n dcmusic
```

### Option B: Helm Chart (Recommended)

```bash
cd /home/dc/Desktop/Prod_DevOps

RDS_ENDPOINT=$(cd terraform && terraform output -raw rds_endpoint)

helm upgrade --install dcmusic helm/dcmusic \
  -f helm/dcmusic/values-dev.yaml \
  -n dcmusic --create-namespace \
  --set backend.image.repository=${AWS_ACCOUNT_ID}.dkr.ecr.ap-south-1.amazonaws.com/dcmusic-backend \
  --set backend.image.tag=v1 \
  --set frontend.image.repository=${AWS_ACCOUNT_ID}.dkr.ecr.ap-south-1.amazonaws.com/dcmusic-frontend \
  --set frontend.image.tag=v1 \
  --set database.host=$(echo $RDS_ENDPOINT | cut -d: -f1) \
  --set database.password="YourSecurePassword123!" \
  --wait

# Verify
helm list -n dcmusic
kubectl get all -n dcmusic
```

### Option C: ArgoCD GitOps (See Section 10)

### 9.1 — Access the Application (NO DNS)

```bash
# Wait for ALB to provision (1-3 minutes)
echo "⏳ Waiting for ALB..."
kubectl get ingress -n dcmusic -w

# Get the ALB DNS URL
ALB_URL=$(kubectl get ingress -n dcmusic -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')
echo ""
echo "✅ ==========================================="
echo "✅  DC Music is Live!"
echo "✅ ==========================================="
echo ""
echo "🌐 Frontend: http://${ALB_URL}"
echo "🔗 Backend API: http://${ALB_URL}/api"
echo ""
echo "✅ ==========================================="
```

> [!NOTE]
> Since we have no Route53/DNS, you access the app via the **ALB DNS hostname** directly (e.g., `k8s-dcmusic-xxxxx.ap-south-1.elb.amazonaws.com`). This is a long URL but works perfectly without any DNS configuration.

### 9.2 — Verify Pods & Logs

```bash
# Check pods are Running
kubectl get pods -n dcmusic
# Expected: 2 backend pods, 2 frontend pods — all Running

# Check backend health
kubectl exec -it $(kubectl get pod -l app=dcmusic-backend -n dcmusic -o jsonpath='{.items[0].metadata.name}') -n dcmusic -- curl -s localhost:8080/actuator/health
# Expected: {"status":"UP"}

# Check backend logs
kubectl logs -f -l app=dcmusic-backend -n dcmusic --tail=50

# Check frontend logs
kubectl logs -f -l app=dcmusic-frontend -n dcmusic --tail=50

# Check HPA status
kubectl get hpa -n dcmusic
```

---

## 10. ArgoCD GitOps Setup

ArgoCD watches your Git repository and automatically syncs Kubernetes deployments when manifests change.

### 10.1 — Install ArgoCD

```bash
cd /home/dc/Desktop/Prod_DevOps

# Run the install script
make argo-install
# OR: bash gitops/argocd/install.sh
```

This script:
1. Creates the `argocd` namespace
2. Installs ArgoCD from official manifests
3. Exposes it via LoadBalancer (HTTP, no DNS needed)
4. Prints access instructions

### 10.2 — Access ArgoCD UI

```bash
# Get ArgoCD admin password
ARGO_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
echo "ArgoCD Admin Password: $ARGO_PASSWORD"

# Get ArgoCD URL
ARGO_URL=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ArgoCD URL: http://${ARGO_URL}"

# Login:
#   Username: admin
#   Password: (printed above)
```

### 10.3 — Register Your Application

First, update the ArgoCD application manifest with your Git repo URL:

```bash
# Edit the ArgoCD application manifest
nano gitops/apps/dcmusic-dev.yaml
# Change spec.source.repoURL to YOUR GitHub repository URL
# e.g., https://github.com/YOUR_USERNAME/Prod_DevOps.git
```

Then apply:

```bash
# Apply the ArgoCD application (dev — auto-sync enabled)
kubectl apply -f gitops/apps/dcmusic-dev.yaml

# Check sync status
kubectl get applications -n argocd
# Expected: dcmusic-dev   Synced   Healthy
```

### 10.4 — How ArgoCD Works Now

```
1. You push code → GitHub
2. Jenkins builds → pushes image to ECR → updates image tag in values.yaml → pushes to Git
3. ArgoCD detects the change (polls every 3 minutes)
4. ArgoCD applies the new manifests → rolling update → zero downtime
```

---

## 11. Prometheus & Grafana Monitoring

### 11.1 — Install Monitoring Stack

```bash
cd /home/dc/Desktop/Prod_DevOps

# Run the install script
make mon-install
# OR: bash monitoring/install.sh
```

This installs:
- **Prometheus** — scrapes metrics from pods, nodes, and K8s API
- **Grafana** — dashboards for visualization (exposed via LoadBalancer)
- **Alertmanager** — routes alerts to Slack/Email
- **node-exporter** — host-level metrics
- **kube-state-metrics** — Kubernetes object metrics
- Custom alerting rules for DC Music
- DC Music Grafana dashboard

### 11.2 — Access Grafana

```bash
# Get Grafana URL
GRAFANA_URL=$(kubectl get svc prometheus-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Grafana URL: http://${GRAFANA_URL}"
echo "Username: admin"
echo "Password: admin"
```

### 11.3 — Access Prometheus & Alertmanager (via port-forward)

```bash
# Prometheus UI (open http://localhost:9090)
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring &

# Alertmanager UI (open http://localhost:9093)
kubectl port-forward svc/prometheus-kube-prometheus-alertmanager 9093:9093 -n monitoring &
```

### 11.4 — Verify Prometheus is Scraping DC Music

Open Prometheus UI (http://localhost:9090) → **Status** → **Targets**

Look for targets from `dcmusic` namespace pods. You should see the backend's `/actuator/prometheus` endpoint being scraped.

### 11.5 — Custom Alert Rules

The following alerts are pre-configured in `monitoring/prometheus/alerting-rules.yaml`:

| Alert Name | Trigger Condition | Severity |
|---|---|---|
| `HighPodCPU` | Pod CPU > 80% for 5 minutes | Warning |
| `PodCrashLooping` | Pod restart count > 3 in 10 minutes | Critical |
| `HighErrorRate` | HTTP 5xx responses > 5% for 2 minutes | Critical |
| `PodNotReady` | Pod not Ready for 5 minutes | Warning |
| `HighMemoryUsage` | Pod memory > 85% for 5 minutes | Warning |

---

## 12. Jenkins CI/CD Setup

### 12.1 — Jenkins Installation (If Not Already Installed)

```bash
# Install Jenkins on Ubuntu
sudo apt update
sudo apt install -y fontconfig openjdk-17-jre
sudo wget -O /usr/share/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc]" \
  https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt update
sudo apt install -y jenkins

# Start Jenkins
sudo systemctl start jenkins
sudo systemctl enable jenkins

# Get initial admin password
sudo cat /var/lib/jenkins/secrets/initialAdminPassword

# Access Jenkins: http://YOUR_IP:8080
```

### 12.2 — Required Jenkins Plugins

Install these plugins from **Manage Jenkins** → **Plugins** → **Available Plugins**:

| Plugin Name | Plugin ID | Purpose |
|---|---|---|
| **Pipeline** | `workflow-aggregator` | Jenkinsfile pipeline support |
| **Pipeline: Stage View** | `pipeline-stage-view` | Visual pipeline stages |
| **AWS Credentials** | `aws-credentials` | Store AWS access keys |
| **Docker Pipeline** | `docker-workflow` | Docker build/push in pipeline |
| **NodeJS** | `nodejs` | NodeJS tool auto-installer |
| **Kubernetes CLI** | `kubernetes-cli` | kubectl in pipeline (optional) |
| **Git** | `git` | Git checkout |
| **Credentials Binding** | `credentials-binding` | Inject creds into build |

### 12.3 — Jenkins Global Tool Configuration

Go to **Manage Jenkins** → **Tools**:

#### Maven Installation
- Click **"Add Maven"**
- Name: `Maven-3.9`
- Check **"Install automatically"**
- Version: `3.9.6`

#### NodeJS Installation
- Click **"Add NodeJS"**
- Name: `Node-20`
- Check **"Install automatically"**
- Version: `20.x`

### 12.4 — Jenkins Credentials

Go to **Manage Jenkins** → **Credentials** → **System** → **Global credentials** → **Add Credentials**:

#### Credential 1: AWS Credentials
- Kind: **AWS Credentials**
- ID: `aws-credentials`
- Access Key ID: `<YOUR_AWS_ACCESS_KEY_ID>`
- Secret Access Key: `<YOUR_AWS_SECRET_ACCESS_KEY>`

#### Credential 2: RDS Password
- Kind: **Secret text**
- ID: `rds-password`
- Secret: `YourSecurePassword123!` (your RDS password)

#### Credential 3: GitHub Token (for GitOps repo updates)
- Kind: **Secret text**
- ID: `github-token`
- Secret: `<YOUR_GITHUB_PERSONAL_ACCESS_TOKEN>`

### 12.5 — Install Tools on Jenkins Agent

The Jenkins agent (the machine running builds) needs these CLI tools:

```bash
# On the Jenkins server/agent:

# Docker (Jenkins user must be in docker group)
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins

# AWS CLI
# (Follow install from Section 1)

# kubectl
# (Follow install from Section 1)

# Helm
# (Follow install from Section 1)

# Trivy
# (Follow install from Section 1)

# Verify Jenkins can use them
sudo -u jenkins docker --version
sudo -u jenkins aws --version
sudo -u jenkins kubectl version --client
sudo -u jenkins helm version
sudo -u jenkins trivy --version
```

### 12.6 — Create Jenkins Pipeline Job

1. **Jenkins Dashboard** → **New Item**
2. Name: `dcmusic-ci`
3. Type: **Pipeline**
4. Pipeline Definition: **Pipeline script from SCM**
   - SCM: **Git**
   - Repository URL: `https://github.com/YOUR_USERNAME/Prod_DevOps.git`
   - Branch: `*/main`
   - Script Path: `Jenkinsfile`
5. Build Triggers: Check **"GitHub hook trigger for GITScm polling"**
6. **Save**

### 12.7 — Create Infrastructure Pipeline Job

1. **Jenkins Dashboard** → **New Item**
2. Name: `dcmusic-infra`
3. Type: **Pipeline**
4. Pipeline Definition: **Pipeline script from SCM**
   - SCM: **Git**
   - Repository URL: Same as above
   - Branch: `*/main`
   - Script Path: `Jenkinsfile.infra`
5. Build Triggers: **None** (manual trigger only)
6. **Save**

### 12.8 — Setup GitHub Webhook (Auto-trigger on Push)

1. Go to your GitHub repo → **Settings** → **Webhooks** → **Add webhook**
2. Payload URL: `http://YOUR_JENKINS_IP:8080/github-webhook/`
3. Content type: `application/json`
4. Events: **Just the push event**
5. **Save**

### 12.9 — Jenkins Pipeline Stages (What the Jenkinsfile Does)

| Stage | What Happens | Tools Used |
|---|---|---|
| 1. **Checkout** | Pulls latest code from GitHub | Git |
| 2. **AWS Setup** | Gets AWS Account ID, constructs ECR URLs | AWS CLI |
| 3. **Unit Tests** | Runs `mvn test` + `npm test` in parallel | Maven, Node |
| 4. **Build** | Runs `mvn package` + `npm run build` in parallel | Maven, Node |
| 5. **Docker Build** | Builds both images tagged with `BUILD_NUMBER` | Docker |
| 6. **Security Scan** | Trivy scans for CRITICAL vulnerabilities | Trivy |
| 7. **Push to ECR** | Pushes images with `:build-N` and `:latest` tags | Docker, AWS CLI |
| 8. **Update K8s Manifests** | Updates image tag in Helm values.yaml | sed, Git |
| 9. **Deploy to EKS** | Runs `helm upgrade` or `kubectl set image` | Helm, kubectl |
| 10. **Verify Deployment** | Waits for rollout completion | kubectl |

### 12.10 — Run Your First Build

1. Go to `dcmusic-ci` job → **Build Now**
2. Watch the console output
3. Verify all 10 stages pass
4. Check the app is updated: `kubectl get pods -n dcmusic`

---

## 13. End-to-End Verification

### 13.1 — Full System Check

```bash
echo "=== 1. EKS Cluster ==="
kubectl get nodes
echo ""

echo "=== 2. DC Music Pods ==="
kubectl get pods -n dcmusic
echo ""

echo "=== 3. Services ==="
kubectl get svc -n dcmusic
echo ""

echo "=== 4. Ingress (ALB URL) ==="
kubectl get ingress -n dcmusic
echo ""

echo "=== 5. HPA Status ==="
kubectl get hpa -n dcmusic
echo ""

echo "=== 6. ArgoCD ==="
kubectl get applications -n argocd 2>/dev/null || echo "ArgoCD not installed"
echo ""

echo "=== 7. Monitoring ==="
kubectl get pods -n monitoring 2>/dev/null || echo "Monitoring not installed"
echo ""

echo "=== 8. ALB URL ==="
ALB_URL=$(kubectl get ingress -n dcmusic -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
echo "🌐 App URL: http://${ALB_URL}"
echo ""

echo "=== 9. ArgoCD URL ==="
ARGO_URL=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
echo "🔄 ArgoCD: http://${ARGO_URL}"
echo ""

echo "=== 10. Grafana URL ==="
GRAFANA_URL=$(kubectl get svc prometheus-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
echo "📊 Grafana: http://${GRAFANA_URL}"
```

### 13.2 — Test the Complete Flow

```bash
# 1. Make a code change
echo "// test change" >> frontend/src/App.jsx

# 2. Commit and push
git add . && git commit -m "test: verify CI/CD pipeline"
git push origin main

# 3. Watch Jenkins build
#    → Jenkins Dashboard → dcmusic-ci → latest build → Console Output

# 4. Watch ArgoCD sync
#    → ArgoCD UI → dcmusic-dev → should auto-sync within 3 minutes

# 5. Verify new pods
kubectl get pods -n dcmusic
# Should see new pods rolling out

# 6. Check Grafana for metrics
#    → Grafana → Dashboards → DC Music Dashboard
```

---

## 14. Cost Management & Cleanup

### 14.1 — Daily Cost Saving (Scale Down When Not Using)

```bash
# Scale EKS nodes to 0 (stops EC2 billing, ~$33/mo savings)
aws eks update-nodegroup-config \
  --cluster-name dcmusic-eks \
  --nodegroup-name dcmusic-eks-general \
  --scaling-config minSize=0,desiredSize=0,maxSize=3 \
  --region ap-south-1

# Scale back up when needed
aws eks update-nodegroup-config \
  --cluster-name dcmusic-eks \
  --nodegroup-name dcmusic-eks-general \
  --scaling-config minSize=1,desiredSize=2,maxSize=3 \
  --region ap-south-1
```

> [!CAUTION]
> Even with nodes at 0, the **EKS control plane (\$73/mo)** and **NAT Gateway (\$32/mo)** still charge. For full cost elimination, run `terraform destroy`.

### 14.2 — Full Cleanup (Destroy Everything)

```bash
cd /home/dc/Desktop/Prod_DevOps

# Step 1: Delete K8s resources first (removes ALBs, etc.)
kubectl delete -f k8s/base/ -R --ignore-not-found
helm uninstall dcmusic -n dcmusic --ignore-not-found
helm uninstall prometheus -n monitoring --ignore-not-found
kubectl delete -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml -n argocd --ignore-not-found

# Step 2: Wait for ALBs to be deleted (check AWS console)
echo "⏳ Waiting 60s for ALBs to be deleted..."
sleep 60

# Step 3: Destroy Terraform infrastructure
cd terraform
terraform destroy -var="db_password=YourSecurePassword123!"
# Type 'yes' to confirm

# Step 4: Delete Terraform remote state (optional — keeps state for re-create)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3 rb s3://dcmusic-tf-state-${AWS_ACCOUNT_ID} --force
aws dynamodb delete-table --table-name dcmusic-tf-lock --region ap-south-1

echo "✅ All AWS resources destroyed. Monthly bill: $0"
```

---

## 15. Troubleshooting

### Pods in CrashLoopBackOff
```bash
# Check pod logs
kubectl logs <pod-name> -n dcmusic --previous
# Common causes: wrong DB password, RDS endpoint unreachable, missing env vars
```

### ALB Not Provisioning (Ingress has no ADDRESS)
```bash
# Check ALB controller logs
kubectl logs -l app.kubernetes.io/name=aws-load-balancer-controller -n kube-system

# Common causes:
# - ALB controller not installed
# - IRSA role ARN wrong (check serviceaccount annotation)
# - Subnet missing kubernetes.io/role/elb tag
# - Security group doesn't allow inbound HTTP
```

### Nodes Not Joining Cluster
```bash
# Check node group status
aws eks describe-nodegroup --cluster-name dcmusic-eks \
  --nodegroup-name dcmusic-eks-general --region ap-south-1

# Common causes:
# - IAM role missing policies (EKSWorkerNodePolicy, CNI, ECR)
# - Private subnets have no NAT Gateway route
# - Security group blocks kubelet port 10250
```

### RDS Connection Refused
```bash
# Test from a pod
kubectl run mysql-test --rm -it --image=mysql:8.0 -n dcmusic -- \
  mysql -h <RDS_ENDPOINT> -u admin -p

# Common causes:
# - RDS security group doesn't allow port 3306 from EKS node SG
# - RDS in different VPC/subnet than EKS
# - Wrong password in K8s secret
```

### ECR Image Pull Errors (ImagePullBackOff)
```bash
# Check pod events
kubectl describe pod <pod-name> -n dcmusic | grep Events -A 20

# Common causes:
# - Node IAM role missing AmazonEC2ContainerRegistryReadOnly
# - Image tag doesn't exist in ECR
# - ECR repo in different region
```

### HPA Not Scaling
```bash
# Check if metrics-server is running
kubectl get deployment metrics-server -n kube-system

# If not installed, install it:
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Check HPA status
kubectl describe hpa -n dcmusic
```

### Jenkins Build Fails
```
# Common issues:
# 1. "aws: command not found" → Install AWS CLI on Jenkins agent
# 2. "docker: permission denied" → Add jenkins user to docker group
# 3. "kubectl: command not found" → Install kubectl on Jenkins agent
# 4. "Cannot connect to EKS" → Run aws eks update-kubeconfig as jenkins user
# 5. "Trivy: command not found" → Install Trivy on Jenkins agent
```

### Terraform State Lock
```bash
# If terraform is stuck on a lock:
terraform force-unlock <LOCK_ID>
```

---

## Quick Reference — All Access URLs

| Service | How to Get URL | Default Credentials |
|---|---|---|
| **DC Music App** | `kubectl get ingress -n dcmusic` | (your app login) |
| **ArgoCD** | `kubectl get svc argocd-server -n argocd` | admin / (see 10.2) |
| **Grafana** | `kubectl get svc prometheus-grafana -n monitoring` | admin / admin |
| **Prometheus** | `kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring` | — |
| **Alertmanager** | `kubectl port-forward svc/prometheus-kube-prometheus-alertmanager 9093:9093 -n monitoring` | — |
| **Jenkins** | `http://YOUR_JENKINS_IP:8080` | (set during setup) |

---

## Quick Reference — Make Commands

```bash
make help          # Show all available commands
make dev-up        # Start local Docker stack
make dev-down      # Stop local Docker stack
make build         # Build backend + frontend
make docker        # Build Docker images
make tf-init       # Initialize Terraform
make tf-plan       # Preview infra changes
make tf-apply      # Apply infra changes
make eks-config    # Configure kubectl for EKS
make k8s-apply     # Apply raw K8s manifests
make helm-dev      # Deploy with Helm (dev)
make helm-prod     # Deploy with Helm (prod)
make argo-install  # Install ArgoCD
make mon-install   # Install monitoring
make status        # Show dcmusic namespace resources
make logs-be       # Follow backend logs
make logs-fe       # Follow frontend logs
```

---

*Generated for DC Music — Production DevOps on AWS EKS*
*Optimized for AWS Free Tier | No DNS Required | HTTP Only*
