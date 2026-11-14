# 🛠️ Jenkins CI/CD Complete Implementation Guide — DC Music

> Full step-by-step guide to set up, configure, and run both Jenkins pipelines. Every step, every click, every command — based on the actual project files.

---

## 📑 Table of Contents

1. [Architecture Overview — Two Pipelines](#1-architecture-overview--two-pipelines)
2. [Complete Project Structure Reference](#2-complete-project-structure-reference)
3. [Prerequisites Checklist](#3-prerequisites-checklist)
4. [Phase 1 — Jenkins Server Installation](#4-phase-1--jenkins-server-installation)
5. [Phase 2 — Plugin Installation (Step by Step)](#5-phase-2--plugin-installation-step-by-step)
6. [Phase 3 — Global Tool Configuration (Maven & Node)](#6-phase-3--global-tool-configuration-maven--node)
7. [Phase 4 — Credentials Setup (3 Credentials)](#7-phase-4--credentials-setup-3-credentials)
8. [Phase 5 — Install CLI Tools on Jenkins Agent](#8-phase-5--install-cli-tools-on-jenkins-agent)
9. [Phase 6 — Pre-Pipeline AWS Setup (S3 + DynamoDB for Terraform State)](#9-phase-6--pre-pipeline-aws-setup-s3--dynamodb-for-terraform-state)
10. [Phase 7 — Pipeline 1: Infrastructure (`Jenkinsfile.infra`) — Full Walkthrough](#10-phase-7--pipeline-1-infrastructure-jenkinsfileinfra--full-walkthrough)
11. [Phase 8 — Post-Infrastructure: Install ALB Controller & ArgoCD](#11-phase-8--post-infrastructure-install-alb-controller--argocd)
12. [Phase 9 — Pipeline 2: Application (`Jenkinsfile`) — Full Walkthrough](#12-phase-9--pipeline-2-application-jenkinsfile--full-walkthrough)
13. [Phase 10 — GitHub Webhook Setup (Auto-Trigger)](#13-phase-10--github-webhook-setup-auto-trigger)
14. [Phase 11 — Monitoring Setup (Prometheus + Grafana)](#14-phase-11--monitoring-setup-prometheus--grafana)
15. [How to Run Each Pipeline — Quick Reference](#15-how-to-run-each-pipeline--quick-reference)
16. [Pipeline File Code Walkthrough — Line by Line](#16-pipeline-file-code-walkthrough--line-by-line)
17. [Troubleshooting Guide](#17-troubleshooting-guide)
18. [Complete Command Cheat Sheet](#18-complete-command-cheat-sheet)

---

## 1. Architecture Overview — Two Pipelines

This project has **two separate Jenkinsfiles** for two different purposes:

| File | Job Name | Purpose | Stages | When to Run | Trigger |
|---|---|---|---|---|---|
| `Jenkinsfile.infra` | `dcmusic-infra` | Create/update AWS infrastructure (VPC, EKS, RDS, ECR, IAM) using Terraform | **6 stages** | First time + when infra changes needed | **Manual only** (has approval gate) |
| `Jenkinsfile` | `dcmusic-app` | Build → Test → Docker → Trivy scan → ECR → Deploy to EKS → Verify | **10 stages** | Every code change | **Automatic** (webhook) or manual |

### Why Two Pipelines?

```
┌─────────────────────────────────────────────────────────────────────┐
│                      EXECUTION ORDER                                │
│                                                                     │
│   ┌── PHASE A: ONE-TIME SETUP ──────────────────────────────────┐  │
│   │                                                              │  │
│   │  1. Jenkinsfile.infra (RUN FIRST — MANUAL)                  │  │
│   │     ├─ Creates: VPC → Security Groups → ECR → IAM → EKS → RDS│  │
│   │     ├─ Has: Manual Approval Gate ⏸️ (review before apply)   │  │
│   │     ├─ Takes: ~15-20 minutes                                │  │
│   │     └─ Cost: EKS ~$73/mo + NAT ~$32/mo + RDS (free tier)   │  │
│   │                                                              │  │
│   │  2. Post-Infra Setup (MANUAL — local commands)              │  │
│   │     ├─ Install AWS Load Balancer Controller                 │  │
│   │     ├─ Install ArgoCD (optional)                            │  │
│   │     └─ Install Prometheus + Grafana (optional)              │  │
│   └──────────────────────────────────────────────────────────────┘  │
│                            ↓                                        │
│   ┌── PHASE B: EVERY CODE CHANGE ───────────────────────────────┐  │
│   │                                                              │  │
│   │  3. Jenkinsfile (RUNS ON EVERY PUSH — AUTOMATIC)            │  │
│   │     ├─ Checkout → AWS Setup → Tests → Build                 │  │
│   │     ├─ Docker Build → Trivy Scan → Push ECR                 │  │
│   │     ├─ Update Manifests → Helm Deploy → Verify              │  │
│   │     ├─ Takes: ~5-8 minutes                                  │  │
│   │     └─ Zero-downtime rolling update                         │  │
│   └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Design Decisions in Our Jenkinsfiles

| Decision | Why |
|---|---|
| Infra pipeline has Manual Approval | Prevents accidental AWS resource creation/destruction |
| App pipeline has NO approval | Speed — every push deploys automatically |
| Parallel test + build stages | Saves ~2 minutes per build |
| Trivy scan is soft-fail | Marks build UNSTABLE (⚠️) not FAILED — deploy continues |
| Helm with kubectl fallback | Helm is primary, kubectl `set image` if Helm chart fails |
| `docker image prune` in post | Prevents disk fill on Jenkins server |

---

## 2. Complete Project Structure Reference

These are ALL the files both Jenkinsfiles interact with:

```
/home/dc/Desktop/Prod_DevOps/
├── Jenkinsfile                          ← App CI/CD (10 stages)
├── Jenkinsfile.infra                    ← Infra pipeline (6 stages)
├── Makefile                             ← Developer shortcuts
│
├── backend/
│   ├── Dockerfile                       ← Multi-stage: Maven build → JRE Alpine
│   ├── pom.xml                          ← Spring Boot 3.2 + Java 17
│   └── src/main/resources/
│       ├── application.properties       ← Local dev config
│       ├── application-aws.properties   ← AWS/EC2 config
│       └── application-eks.properties   ← EKS + Actuator + Prometheus metrics
│
├── frontend/
│   ├── Dockerfile                       ← Multi-stage: Node build → Nginx Alpine
│   ├── package.json                     ← React + Vite
│   └── src/                             ← React components
│
├── terraform/                           ← Jenkinsfile.infra operates HERE
│   ├── provider.tf                      ← AWS provider + S3 backend config
│   ├── main.tf                          ← Wires 6 modules together
│   ├── variables.tf                     ← All configurable inputs
│   ├── outputs.tf                       ← EKS endpoint, RDS endpoint, ECR URLs
│   └── modules/
│       ├── vpc/                          ← VPC, subnets, NAT gateway, IGW
│       ├── security/                     ← Security groups (EKS, nodes, RDS)
│       ├── ecr/                          ← Docker image repos (backend + frontend)
│       ├── iam/                          ← EKS cluster role + node role
│       ├── eks/                          ← EKS cluster, node group, OIDC, LB role
│       └── rds/                          ← MySQL db.t3.micro (free tier)
│
├── helm/dcmusic/                        ← Jenkinsfile deploys THIS
│   ├── Chart.yaml                       ← Chart metadata
│   ├── values.yaml                      ← Default values (ACCOUNT_ID placeholders)
│   ├── values-dev.yaml                  ← Dev overrides
│   ├── values-prod.yaml                 ← Prod overrides
│   └── templates/
│       ├── _helpers.tpl                 ← Template helper functions
│       ├── namespace.yaml
│       ├── serviceaccount.yaml
│       ├── backend-deployment.yaml
│       ├── backend-service.yaml
│       ├── backend-configmap.yaml
│       ├── backend-secret.yaml
│       ├── backend-hpa.yaml
│       ├── frontend-deployment.yaml
│       ├── frontend-service.yaml
│       ├── frontend-configmap.yaml
│       ├── frontend-hpa.yaml
│       ├── ingress.yaml                 ← ALB Ingress (internet-facing)
│       └── pdb.yaml                     ← Pod Disruption Budgets
│
├── k8s/base/                            ← Raw K8s manifests (alternative to Helm)
│   ├── namespace.yaml
│   ├── ingress.yaml
│   ├── pdb-backend.yaml
│   ├── pdb-frontend.yaml
│   ├── backend/                         ← deployment, service, hpa, configmap, secret
│   └── frontend/                        ← deployment, service, hpa, configmap
│
├── gitops/
│   ├── apps/
│   │   ├── dcmusic-dev.yaml             ← ArgoCD Application (auto-sync)
│   │   └── dcmusic-prod.yaml            ← ArgoCD Application (manual sync)
│   └── argocd/
│       └── install.sh                   ← ArgoCD installation script
│
└── monitoring/
    ├── install.sh                       ← Prometheus + Grafana Helm install
    └── prometheus/
        ├── values.yaml                  ← Stack config (LoadBalancer, resources)
        └── alerting-rules.yaml          ← 5 alert rules
```

---

## 3. Prerequisites Checklist

Before starting, verify you have **ALL** of these:

### AWS Account Setup

- [ ] **AWS Account** (Free Tier) — [sign up here](https://aws.amazon.com/free/)
- [ ] **IAM User** with programmatic access (Access Key ID + Secret Access Key)
- [ ] **IAM User Permissions** — Attach these managed policies:
  - `AmazonEKSClusterPolicy`
  - `AmazonEKSWorkerNodePolicy`
  - `AmazonEKS_CNI_Policy`
  - `AmazonEC2ContainerRegistryFullAccess`
  - `AmazonRDSFullAccess`
  - `AmazonVPCFullAccess`
  - `AmazonS3FullAccess`
  - `AmazonDynamoDBFullAccess`
  - `IAMFullAccess`
  - Or simply use `AdministratorAccess` (for learning — NOT recommended for production)

### Local Machine Setup

- [ ] **AWS CLI v2** installed and configured (`aws configure` done)
- [ ] **Git** installed and configured
- [ ] **GitHub repository** containing this project (push your code)

### Jenkins Server Requirements

- [ ] **Linux server** (Ubuntu 22.04+ recommended) — can be:
  - Your local machine
  - An EC2 instance (t3.medium or larger recommended)
  - Any Linux VM with internet access
- [ ] **Minimum 4GB RAM** (8GB recommended)
- [ ] **Minimum 20GB disk** (30GB recommended)
- [ ] **Ports open**: 8080 (Jenkins UI)

### What You Need to Know Before Starting

| Item | Specific Value Used in Code |
|---|---|
| AWS Region | `ap-south-1` (Mumbai) — hardcoded in both Jenkinsfiles |
| Project Name | `dcmusic` — used for ECR repos, namespaces, Helm release |
| EKS Cluster Name | `dcmusic-eks` — referenced in kubeconfig commands |
| RDS Instance | `db.t3.micro` (Free Tier) |
| EKS Node Type | `t3.small` (2 vCPU, 2GB RAM — minimum for EKS) |
| Kubernetes Version | `1.29` |

> ⚠️ **COST WARNING**: EKS is NOT free tier. Expected costs:
> - EKS control plane: ~$73/month
> - NAT Gateway: ~$32/month
> - t3.small nodes (×2): ~$30/month
> - **Total: ~$135-160/month**

---

## 4. Phase 1 — Jenkins Server Installation

### Step 1: Install Java 17 (Jenkins requires Java)

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install Java 17 JDK
sudo apt install -y openjdk-17-jdk openjdk-17-jre fontconfig

# Verify installation
java -version
# Expected output: openjdk version "17.x.x"
```

### Step 2: Add Jenkins Repository & Install Jenkins

```bash
# Add Jenkins GPG signing key
sudo wget -O /usr/share/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key

# Add Jenkins apt repository
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian-stable binary/" | \
  sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

# Install Jenkins
sudo apt update
sudo apt install -y jenkins
```

### Step 3: Start Jenkins Service

```bash
# Reload systemd, enable and start Jenkins
sudo systemctl daemon-reload
sudo systemctl enable jenkins
sudo systemctl start jenkins

# Verify it's running
sudo systemctl status jenkins
# Expected: ● jenkins.service - Jenkins ... Active: active (running)
```

### Step 4: Unlock Jenkins (First-Time Browser Setup)

1. **Open browser**: `http://<YOUR_SERVER_IP>:8080`
   - If local machine: `http://localhost:8080`
   - If EC2: `http://<EC2_PUBLIC_IP>:8080` (ensure port 8080 is open in Security Group)

2. **Get the initial admin password**:
   ```bash
   sudo cat /var/lib/jenkins/secrets/initialAdminPassword
   ```
   Copy the output (a long hex string like `a1b2c3d4e5f6...`)

3. **Paste** the password in the browser unlock page

4. Click **"Install suggested plugins"** → Wait for all plugins to install (~3-5 minutes)

5. **Create your admin user**:
   - Username: `admin` (or your choice)
   - Password: `<your-strong-password>`
   - Full name: `DC Admin`
   - Email: `your@email.com`

6. **Jenkins URL**: Keep the default (`http://<YOUR_IP>:8080/`) → Click **"Save and Finish"**

7. Click **"Start using Jenkins"** → You're now on the Jenkins Dashboard

---

## 5. Phase 2 — Plugin Installation (Step by Step)

### Step 1: Navigate to Plugin Manager

```
Jenkins Dashboard → Click "Manage Jenkins" (left sidebar)
                  → Click "Plugins"
                  → Click "Available plugins" tab
```

### Step 2: Search and Select These 8 Plugins

In the search box, search for each one and **tick the checkbox**:

| # | Search For | Plugin to Select | What It Does | Used By |
|---|---|---|---|---|
| 1 | `pipeline` | **Pipeline** (`workflow-aggregator`) | Enables `Jenkinsfile` pipeline execution | Both pipelines |
| 2 | `stage view` | **Pipeline: Stage View** | Visual stage diagram on job page | Both pipelines |
| 3 | `aws credentials` | **AWS Credentials** | Stores AWS keys, injects via `withCredentials` | Both pipelines |
| 4 | `docker pipeline` | **Docker Pipeline** | Docker build/push in pipeline | `Jenkinsfile` |
| 5 | `nodejs` | **NodeJS** | Auto-installs Node.js for frontend build | `Jenkinsfile` |
| 6 | `kubernetes cli` | **Kubernetes CLI** | kubectl access in pipeline | `Jenkinsfile` |
| 7 | `credentials binding` | **Credentials Binding** | Injects secrets as env vars (`string()`, etc.) | Both pipelines |
| 8 | `git` | **Git** | Git checkout support | Both pipelines |

### Step 3: Install All Selected Plugins

1. Click **"Download now and install after restart"** (bottom of page)
2. On the next screen, check: ✅ **"Restart Jenkins when installation is complete and no jobs are running"**
3. Wait for Jenkins to restart (~1-2 minutes)
4. Login again with your admin credentials

### Step 4: Verify Plugins Are Installed

```
Manage Jenkins → Plugins → Installed plugins
```
Search for each one — all 8 should show as "Installed".

---

## 6. Phase 3 — Global Tool Configuration (Maven & Node)

> ⚠️ The names MUST match EXACTLY what's in the Jenkinsfile `tools {}` block:
> ```groovy
> tools {
>     maven 'Maven-3.9'    // ← Must match
>     nodejs 'Node-20'     // ← Must match
> }
> ```

### Step 1: Navigate

```
Jenkins Dashboard → "Manage Jenkins" → "Tools"
```

### Step 2: Configure Maven

1. Scroll down to **"Maven"** section
2. Click **"Add Maven"**
3. Fill in:
   - **Name**: `Maven-3.9` ⚠️ *Exact match required*
   - ✅ Check **"Install automatically"**
   - **Version**: Select `3.9.6` (or latest 3.9.x available)

### Step 3: Configure NodeJS

1. Scroll down to **"NodeJS"** section
2. Click **"Add NodeJS"**
3. Fill in:
   - **Name**: `Node-20` ⚠️ *Exact match required*
   - ✅ Check **"Install automatically"**
   - **Version**: Select `NodeJS 20.x.x` (e.g., `20.18.0`)

### Step 4: Save

Click **"Save"** at the bottom of the page.

> 💡 Jenkins will auto-download these tools on the first build run. The first build will take a few extra minutes.

---

## 7. Phase 4 — Credentials Setup (3 Credentials)

> ⚠️ The credential IDs MUST match EXACTLY what's in both Jenkinsfiles:
> ```groovy
> // In Jenkinsfile & Jenkinsfile.infra:
> credentialsId: 'aws-credentials'    // ← Must match
> credentialsId: 'rds-password'       // ← Must match
> ```

### Step 1: Navigate to Credentials

```
Jenkins Dashboard → "Manage Jenkins" → "Credentials"
                  → Click "System"
                  → Click "Global credentials (unrestricted)"
                  → Click "Add Credentials" (left sidebar)
```

### Credential 1: AWS Access Keys

| Field | Value |
|---|---|
| **Kind** | `AWS Credentials` *(dropdown)* |
| **Scope** | `Global` |
| **ID** | `aws-credentials` ⚠️ *Exact match required* |
| **Description** | `AWS IAM keys for EKS/ECR/Terraform` |
| **Access Key ID** | *Your AWS Access Key ID (e.g., AKIA...)* |
| **Secret Access Key** | *Your AWS Secret Access Key* |

Click **"Create"**

### Credential 2: RDS Database Password

Click **"Add Credentials"** again:

| Field | Value |
|---|---|
| **Kind** | `Secret text` *(dropdown)* |
| **Scope** | `Global` |
| **ID** | `rds-password` ⚠️ *Exact match required* |
| **Description** | `RDS MySQL master password` |
| **Secret** | *Your chosen DB password (e.g., `MySecure#Pass2024!`)* |

Click **"Create"**

> 💡 Remember this password — you'll need it when configuring Helm values and K8s secrets.

### Credential 3: GitHub Token (Optional — for GitOps auto-commit)

Click **"Add Credentials"** again:

| Field | Value |
|---|---|
| **Kind** | `Secret text` |
| **Scope** | `Global` |
| **ID** | `github-token` |
| **Description** | `GitHub PAT for gitops push` |
| **Secret** | `ghp_xxxxxxxxxxxx` *(your GitHub Personal Access Token)* |

Click **"Create"**

### Step 2: Verify All Credentials Exist

```
Manage Jenkins → Credentials → System → Global credentials
```

You should see:
```
ID                  Kind                  Description
aws-credentials     AWS Credentials       AWS IAM keys for EKS/ECR/Terraform
rds-password        Secret text           RDS MySQL master password
github-token        Secret text           GitHub PAT for gitops push
```

---

## 8. Phase 5 — Install CLI Tools on Jenkins Agent

> The Jenkins agent (the machine running builds) needs these tools installed at the **OS level**. Jenkins manages Maven & Node via plugins (Phase 3), but these must be installed manually.

### Which Pipeline Needs Which Tool?

| Tool | `Jenkinsfile.infra` | `Jenkinsfile` |
|---|---|---|
| Docker | ❌ | ✅ Stage 5, 6, 7 |
| AWS CLI | ✅ All stages | ✅ Stage 2, 7, 9, 10 |
| Terraform | ✅ Stage 2, 3, 5 | ❌ |
| kubectl | ❌ | ✅ Stage 9, 10 |
| Helm | ❌ | ✅ Stage 9 |
| Trivy | ❌ | ✅ Stage 6 |

### 8.1 — Docker

```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# ⚠️ CRITICAL: Add jenkins user to docker group
# Without this, Jenkins builds will fail with "permission denied"
sudo usermod -aG docker jenkins

# Restart Jenkins to pick up the new group
sudo systemctl restart jenkins

# Verify Docker works as jenkins user
sudo -u jenkins docker ps
# Expected: empty container list, NO permission error
```

### 8.2 — AWS CLI v2

```bash
# Download and install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
sudo apt install -y unzip  # if unzip not installed
unzip awscliv2.zip
sudo ./aws/install

# Verify
sudo -u jenkins aws --version
# Expected: aws-cli/2.x.x Python/3.x.x Linux/x86_64
```

### 8.3 — Terraform

```bash
# Add HashiCorp GPG key and repository
wget -O- https://apt.releases.hashicorp.com/gpg | \
  gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt-get update && sudo apt-get install -y terraform

# Verify
sudo -u jenkins terraform -version
# Expected: Terraform v1.5.0+ (any 1.5+ version)
```

### 8.4 — kubectl

```bash
# Download latest stable kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

# Install
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Verify
sudo -u jenkins kubectl version --client
# Expected: Client Version: v1.29.x (or newer)
```

### 8.5 — Helm 3

```bash
# Install Helm 3 via official script
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify
sudo -u jenkins helm version
# Expected: version.BuildInfo{Version:"v3.x.x", ...}
```

### 8.6 — Trivy (Container Security Scanner)

```bash
# Add Trivy repository
sudo apt-get install -y wget apt-transport-https gnupg lsb-release

wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | \
  gpg --dearmor | sudo tee /usr/share/keyrings/trivy.gpg > /dev/null

echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] \
  https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | \
  sudo tee /etc/apt/sources.list.d/trivy.list

sudo apt-get update && sudo apt-get install -y trivy

# Verify
sudo -u jenkins trivy --version
# Expected: Version: 0.50.0+ (any recent version)
```

### 8.7 — Final Verification Script

Run this single script to confirm ALL tools work as the `jenkins` user:

```bash
echo "============================================="
echo "  Verifying ALL tools as jenkins user"
echo "============================================="
sudo -u jenkins bash -c '
  echo "1. Docker:    $(docker --version 2>&1)"
  echo "2. AWS CLI:   $(aws --version 2>&1)"
  echo "3. Terraform: $(terraform -version 2>/dev/null | head -1)"
  echo "4. kubectl:   $(kubectl version --client 2>&1 | head -1)"
  echo "5. Helm:      $(helm version --short 2>/dev/null)"
  echo "6. Trivy:     $(trivy --version 2>&1 | head -1)"
  echo ""
  echo "============================================="
  echo "  All 6 tools verified ✅"
  echo "============================================="
'
```

**Expected output** — all 6 lines should show version numbers, no errors:
```
1. Docker:    Docker version 24.x.x, build xxxxx
2. AWS CLI:   aws-cli/2.x.x Python/3.x.x Linux/x86_64
3. Terraform: Terraform v1.x.x
4. kubectl:   Client Version: v1.x.x
5. Helm:      v3.x.x
6. Trivy:     Version: 0.x.x
```

---

## 9. Phase 6 — Pre-Pipeline AWS Setup (S3 + DynamoDB for Terraform State)

> ⚠️ This must be done BEFORE running `Jenkinsfile.infra`. The infra pipeline's `terraform init` expects these to exist.

### Why?

Our `terraform/provider.tf` configures a **remote S3 backend**:
```hcl
backend "s3" {
  bucket         = "dcmusic-tf-state-bucket"   # S3 bucket for state
  key            = "dev/terraform.tfstate"      # Path inside bucket
  region         = "ap-south-1"
  dynamodb_table = "dcmusic-tf-lock"            # DynamoDB for locking
  encrypt        = true
}
```

The `Jenkinsfile.infra` overrides the bucket name dynamically with your Account ID:
```groovy
terraform init \
  -backend-config="bucket=dcmusic-tf-state-${env.AWS_ACCOUNT_ID}" \
  -backend-config="key=dev/terraform.tfstate" \
  ...
```

### Step 1: Get Your AWS Account ID

```bash
aws sts get-caller-identity --query Account --output text
# Output: 123456789012 (your 12-digit account ID)
```

### Step 2: Create S3 Bucket for Terraform State

```bash
# Replace with your actual account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create the S3 bucket
aws s3 mb s3://dcmusic-tf-state-${AWS_ACCOUNT_ID} --region ap-south-1

# Enable versioning (so you can recover previous state versions)
aws s3api put-bucket-versioning \
  --bucket dcmusic-tf-state-${AWS_ACCOUNT_ID} \
  --versioning-configuration Status=Enabled

# Verify
aws s3 ls | grep dcmusic
# Expected: 2024-xx-xx xx:xx:xx dcmusic-tf-state-123456789012
```

### Step 3: Create DynamoDB Table for State Locking

```bash
aws dynamodb create-table \
  --table-name dcmusic-tf-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-south-1

# Verify
aws dynamodb describe-table --table-name dcmusic-tf-lock --query 'Table.TableStatus'
# Expected: "ACTIVE"
```

### Step 4: Push Your Code to GitHub

```bash
cd /home/dc/Desktop/Prod_DevOps

# Initialize git if not already done
git init
git remote add origin https://github.com/<YOUR_USERNAME>/Prod_DevOps.git

# Add all files and push
git add .
git commit -m "Initial commit: DC Music DevOps project"
git push -u origin main
```

---

## 10. Phase 7 — Pipeline 1: Infrastructure (`Jenkinsfile.infra`) — Full Walkthrough

> **This pipeline creates your entire AWS infrastructure. Run it FIRST, ONCE.**

### 10.1 — Create the Jenkins Job

1. Jenkins Dashboard → Click **"New Item"** (left sidebar)
2. **Enter an item name**: `dcmusic-infra`
3. **Select type**: `Pipeline`
4. Click **"OK"**

### 10.2 — Configure the Job

On the configuration page, fill in these sections:

**General:**
- ✅ Check **"Do not allow concurrent builds"**
  - *Why: Prevents two Terraform runs from conflicting*

**Build Triggers:**
- Leave ALL checkboxes **UNCHECKED**
  - *Why: Infrastructure changes should ONLY run manually*

**Pipeline section:**

| Field | Value |
|---|---|
| **Definition** | `Pipeline script from SCM` |
| **SCM** | `Git` |
| **Repository URL** | `https://github.com/<YOUR_USERNAME>/Prod_DevOps.git` |
| **Credentials** | Leave blank (public repo) or select GitHub credentials |
| **Branch Specifier** | `*/main` |
| **Script Path** | `Jenkinsfile.infra` ⚠️ *Not `Jenkinsfile`!* |

Click **"Save"**

### 10.3 — Run the Pipeline

1. On the `dcmusic-infra` job page, click **"Build Now"** (left sidebar)
2. A new build appears in "Build History" (e.g., `#1`)
3. Click on the build number → Click **"Console Output"** to watch live

### 10.4 — What Happens: Stage-by-Stage Walkthrough

```
╔══════════════════════════════════════════════════════════════════╗
║  STAGE 1: CHECKOUT                                    ⏱️ ~10s  ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  📥 Clones your GitHub repo to the Jenkins workspace.           ║
║                                                                  ║
║  Jenkinsfile.infra code:                                        ║
║  ┌──────────────────────────────────────────────────────┐       ║
║  │  stage('Checkout') {                                 │       ║
║  │      steps {                                         │       ║
║  │          checkout scm                                │       ║
║  │      }                                               │       ║
║  │  }                                                   │       ║
║  └──────────────────────────────────────────────────────┘       ║
║                                                                  ║
║  What you see in Console Output:                                ║
║  > git fetch --no-tags --progress -- https://github.com/...    ║
║  > Checking out Revision abc123def456                           ║
║                                                                  ║
║  ✅ If this fails → Check GitHub URL and credentials            ║
╚══════════════════════════════════════════════════════════════════╝
                              ↓
╔══════════════════════════════════════════════════════════════════╗
║  STAGE 2: TERRAFORM INIT                              ⏱️ ~30s  ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  🏗️ Initializes Terraform, connects to S3 backend.             ║
║                                                                  ║
║  What the code does (2 commands):                               ║
║                                                                  ║
║  1. Gets your AWS Account ID dynamically:                       ║
║     aws sts get-caller-identity --query Account --output text   ║
║     → Returns: 123456789012                                     ║
║                                                                  ║
║  2. Initializes Terraform with dynamic backend:                 ║
║     terraform init \                                            ║
║       -backend-config="bucket=dcmusic-tf-state-123456789012" \  ║
║       -backend-config="key=dev/terraform.tfstate" \             ║
║       -backend-config="region=ap-south-1" \                     ║
║       -backend-config="dynamodb_table=dcmusic-tf-lock" \        ║
║       -backend-config="encrypt=true"                            ║
║                                                                  ║
║  Console Output:                                                ║
║  > Initializing modules...                                      ║
║  > Downloading module "vpc"... "security"... "ecr"...           ║
║  > Initializing the backend... (S3)                             ║
║  > Initializing provider plugins...                             ║
║  > - hashicorp/aws v5.x.x                                      ║
║  > - hashicorp/tls v4.x.x                                      ║
║  > Terraform has been successfully initialized! ✅              ║
║                                                                  ║
║  ❌ If this fails:                                               ║
║  → "bucket does not exist" → Re-run Phase 6 Step 2             ║
║  → "error configuring S3" → Check aws-credentials in Jenkins    ║
╚══════════════════════════════════════════════════════════════════╝
                              ↓
╔══════════════════════════════════════════════════════════════════╗
║  STAGE 3: TERRAFORM PLAN                             ⏱️ ~1-2m  ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  📋 Shows what AWS resources will be created.                   ║
║                                                                  ║
║  Command run:                                                   ║
║  terraform plan \                                               ║
║    -var="db_password=<from rds-password credential>" \           ║
║    -var="ec2_key_name=my-key-pair" \                            ║
║    -out=tfplan                                                  ║
║                                                                  ║
║  Console Output (READ THIS CAREFULLY!):                         ║
║  > Plan: ~30 to add, 0 to change, 0 to destroy.                ║
║  >                                                              ║
║  > Resources to create:                                         ║
║  >   module.vpc.aws_vpc.main                                   ║
║  >   module.vpc.aws_subnet.public[0]                            ║
║  >   module.vpc.aws_subnet.public[1]                            ║
║  >   module.vpc.aws_subnet.private[0]                           ║
║  >   module.vpc.aws_subnet.private[1]                           ║
║  >   module.vpc.aws_internet_gateway.main                       ║
║  >   module.vpc.aws_nat_gateway.main                            ║
║  >   module.security.aws_security_group.eks_cluster             ║
║  >   module.security.aws_security_group.eks_nodes               ║
║  >   module.security.aws_security_group.rds                     ║
║  >   module.ecr.aws_ecr_repository.backend                     ║
║  >   module.ecr.aws_ecr_repository.frontend                    ║
║  >   module.iam.aws_iam_role.eks_cluster_role                   ║
║  >   module.iam.aws_iam_role.eks_nodes_role                     ║
║  >   module.eks.aws_eks_cluster.main                            ║
║  >   module.eks.aws_eks_node_group.main                         ║
║  >   module.rds.aws_db_instance.main                            ║
║  >   ... (about 30 resources total)                             ║
║                                                                  ║
║  The plan is SAVED to file 'tfplan' for the apply stage.        ║
║                                                                  ║
║  ⚠️ Review the plan output! Check that:                         ║
║     - It says "add" not "destroy"                               ║
║     - Instance types are what you expect                        ║
║     - Region is ap-south-1                                      ║
╚══════════════════════════════════════════════════════════════════╝
                              ↓
╔══════════════════════════════════════════════════════════════════╗
║  STAGE 4: MANUAL APPROVAL ⏸️                        ⏱️ PAUSED  ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  ⏸️ Pipeline STOPS here and waits for your approval.            ║
║                                                                  ║
║  You will see this in the Jenkins UI:                            ║
║                                                                  ║
║  ┌────────────────────────────────────────────────┐              ║
║  │  Review terraform plan. Proceed?               │              ║
║  │                                                │              ║
║  │  [ Abort ]              [ Apply ]              │              ║
║  └────────────────────────────────────────────────┘              ║
║                                                                  ║
║  WHERE TO FIND THIS PROMPT:                                      ║
║  → Method 1: Look at the build page — "Paused for Input" link  ║
║  → Method 2: Console Output → scroll to bottom → click link    ║
║  → Method 3: Stage View → blue/flashing "Manual Approval" box  ║
║                                                                  ║
║  ACTIONS:                                                        ║
║  ✅ Click "Apply" → Continues to Stage 5 (creates resources)   ║
║  ❌ Click "Abort" → Pipeline stops, NOTHING is created          ║
║                                                                  ║
║  ⚠️ Take your time! There is no timeout. Review the plan       ║
║     output before clicking "Apply".                              ║
╚══════════════════════════════════════════════════════════════════╝
                              ↓
╔══════════════════════════════════════════════════════════════════╗
║  STAGE 5: TERRAFORM APPLY                         ⏱️ ~15-20m   ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  🚀 Creates ALL AWS resources. THIS IS THE BIG ONE.             ║
║                                                                  ║
║  Command run:                                                   ║
║  terraform apply -auto-approve tfplan                           ║
║                                                                  ║
║  Console Output (takes 15-20 minutes):                          ║
║  > module.vpc.aws_vpc.main: Creating...                         ║
║  > module.vpc.aws_vpc.main: Creation complete [3s]              ║
║  > module.vpc.aws_subnet.public[0]: Creating...                 ║
║  > module.vpc.aws_subnet.public[1]: Creating...                 ║
║  > ...                                                          ║
║  > module.eks.aws_eks_cluster.main: Creating...                 ║
║  > module.eks.aws_eks_cluster.main: Still creating... [5m]      ║
║  > module.eks.aws_eks_cluster.main: Still creating... [10m]     ║
║  > module.eks.aws_eks_cluster.main: Creation complete [12m]     ║ ← SLOWEST
║  > ...                                                          ║
║  > module.eks.aws_eks_node_group.main: Creating...              ║
║  > module.eks.aws_eks_node_group.main: Still creating... [3m]   ║
║  > module.eks.aws_eks_node_group.main: Creation complete [5m]   ║
║  > ...                                                          ║
║  > module.rds.aws_db_instance.main: Creating...                 ║
║  > module.rds.aws_db_instance.main: Creation complete [5m]      ║
║  > ...                                                          ║
║  > Apply complete! Resources: 30 added, 0 changed, 0 destroyed ║
║                                                                  ║
║  ⚠️ BE PATIENT! Don't cancel the build!                         ║
║     EKS cluster: ~12 min | Node group: ~5 min | RDS: ~5 min   ║
╚══════════════════════════════════════════════════════════════════╝
                              ↓
╔══════════════════════════════════════════════════════════════════╗
║  STAGE 6: UPDATE KUBECONFIG                           ⏱️ ~10s  ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  🔧 Configures kubectl on Jenkins to connect to the new EKS.   ║
║                                                                  ║
║  Command run:                                                   ║
║  aws eks update-kubeconfig --name dcmusic-eks --region ap-south-1║
║                                                                  ║
║  Console Output:                                                ║
║  > Added new context arn:aws:eks:ap-south-1:XXXX:cluster/dcmusic-eks║
║  >                                                              ║
║  > ✅ INFRASTRUCTURE READY!                                     ║
║  > To configure kubectl on your local machine:                  ║
║  > aws eks update-kubeconfig --name dcmusic-eks --region ap-south-1║
║  > Then verify with: kubectl get nodes                          ║
║                                                                  ║
║  🎉 PIPELINE COMPLETE!                                          ║
╚══════════════════════════════════════════════════════════════════╝
```

### 10.5 — After Infra Pipeline Completes — Verify on Your Local Machine

```bash
# Step 1: Configure YOUR local kubectl to connect to EKS
aws eks update-kubeconfig --name dcmusic-eks --region ap-south-1

# Step 2: Verify nodes are running
kubectl get nodes
# Expected:
# NAME                                    STATUS   ROLES    AGE   VERSION
# ip-10-0-10-xx.ap-south-1.compute...     Ready    <none>   5m    v1.29.x
# ip-10-0-11-xx.ap-south-1.compute...     Ready    <none>   5m    v1.29.x

# Step 3: Check cluster info
kubectl cluster-info
# Expected:
# Kubernetes control plane is running at https://XXXX.gr7.ap-south-1.eks.amazonaws.com

# Step 4: Get Terraform outputs (for next steps)
cd /home/dc/Desktop/Prod_DevOps/terraform
terraform output
# Shows: vpc_id, eks_cluster_endpoint, rds_endpoint, ecr URLs, etc.
```

---

## 11. Phase 8 — Post-Infrastructure: Install ALB Controller & ArgoCD

> ⚠️ These steps must be done AFTER the infra pipeline succeeds but BEFORE running the app pipeline.

### 11.1 — Install AWS Load Balancer Controller (REQUIRED)

The app pipeline deploys an ALB Ingress — the ALB controller must be running in the cluster to create the actual ALB.

```bash
# Step 1: Install cert-manager (dependency for ALB controller)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml
kubectl wait --for=condition=available deployment/cert-manager -n cert-manager --timeout=120s

# Step 2: Get role ARN from Terraform outputs
cd /home/dc/Desktop/Prod_DevOps/terraform
LB_ROLE_ARN=$(terraform output -raw eks_lb_controller_role_arn)
VPC_ID=$(terraform output -raw vpc_id)

echo "LB Role ARN: $LB_ROLE_ARN"
echo "VPC ID: $VPC_ID"

# Step 3: Add EKS Helm chart repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Step 4: Install the ALB controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=dcmusic-eks \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$LB_ROLE_ARN" \
  --set region=ap-south-1 \
  --set vpcId=$VPC_ID

# Step 5: Verify ALB controller is running
kubectl get pods -n kube-system | grep aws-load-balancer
# Expected: aws-load-balancer-controller-xxxx   1/1   Running   0
```

### 11.2 — Install ArgoCD (OPTIONAL — for GitOps)

```bash
# Use the included install script
chmod +x /home/dc/Desktop/Prod_DevOps/gitops/argocd/install.sh
/home/dc/Desktop/Prod_DevOps/gitops/argocd/install.sh

# Or manually:
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Expose ArgoCD UI (LoadBalancer — gives you an ALB DNS)
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo  # newline

# Get the ArgoCD URL
kubectl get svc argocd-server -n argocd
# EXTERNAL-IP column = your ArgoCD URL (ALB DNS hostname)
```

### 11.3 — Update Helm Values with Real AWS Values

Before running the app pipeline, update `helm/dcmusic/values.yaml` with actual values:

```bash
cd /home/dc/Desktop/Prod_DevOps

# Get your Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Get RDS endpoint
RDS_ENDPOINT=$(cd terraform && terraform output -raw rds_endpoint)

# Update ACCOUNT_ID placeholder in values.yaml
sed -i "s/ACCOUNT_ID/${AWS_ACCOUNT_ID}/g" helm/dcmusic/values.yaml

# Update RDS endpoint placeholder
sed -i "s/REPLACE_RDS_ENDPOINT/${RDS_ENDPOINT}/g" helm/dcmusic/values.yaml

# Verify changes
grep -n "repository:\|DATASOURCE_URL" helm/dcmusic/values.yaml

# Commit and push
git add helm/dcmusic/values.yaml
git commit -m "chore: update Helm values with real AWS values"
git push origin main
```

---

## 12. Phase 9 — Pipeline 2: Application (`Jenkinsfile`) — Full Walkthrough

> **Run this AFTER Phase 7 (infra) and Phase 8 (ALB controller) are complete.**

### 12.1 — Create the Jenkins Job

1. Jenkins Dashboard → **"New Item"**
2. **Enter name**: `dcmusic-app`
3. **Select**: `Pipeline`
4. Click **"OK"**

### 12.2 — Configure the Job

**General:**
- ✅ Check **"Do not allow concurrent builds"**

**Build Triggers:**
- ✅ Check **"GitHub hook trigger for GITScm polling"**
  - *This enables automatic builds on git push via webhook*

**Pipeline section:**

| Field | Value |
|---|---|
| **Definition** | `Pipeline script from SCM` |
| **SCM** | `Git` |
| **Repository URL** | `https://github.com/<YOUR_USERNAME>/Prod_DevOps.git` |
| **Branch Specifier** | `*/main` |
| **Script Path** | `Jenkinsfile` ⚠️ *Not `Jenkinsfile.infra`!* |

Click **"Save"**

### 12.3 — Run the Pipeline

1. Click **"Build Now"** on the left sidebar
2. Click the build number in Build History
3. Watch the **Stage View** — 10 stages light up green one by one
4. Or click **"Console Output"** for detailed logs

### 12.4 — What Happens: All 10 Stages Explained

```
╔══════════════════════════════════════════════════════════════════╗
║  STAGE 1: CHECKOUT                                    ⏱️ ~10s  ║
╠══════════════════════════════════════════════════════════════════╣
║  📥 Clones your GitHub repo to Jenkins workspace.               ║
║                                                                  ║
║  Code:  checkout scm                                            ║
║  Console: > Checking out Revision abc123def456                  ║
╚══════════════════════════════════════════════════════════════════╝
                              ↓
╔══════════════════════════════════════════════════════════════════╗
║  STAGE 2: AWS SETUP                                    ⏱️ ~5s  ║
╠══════════════════════════════════════════════════════════════════╣
║  🔑 Gets your Account ID via STS, constructs ECR URLs.         ║
║                                                                  ║
║  Uses credential: 'aws-credentials'                             ║
║                                                                  ║
║  Commands:                                                      ║
║  aws sts get-caller-identity --query Account --output text      ║
║  → Sets: AWS_ACCOUNT_ID = 123456789012                          ║
║  → Sets: ECR_BACKEND  = 123456789012.dkr.ecr.ap-south-1...    ║
║  → Sets: ECR_FRONTEND = 123456789012.dkr.ecr.ap-south-1...    ║
║                                                                  ║
║  Console Output:                                                ║
║  ✅ AWS Account ID: 123456789012                                ║
║  ✅ Backend ECR:  123456789012.dkr.ecr.ap-south-1.amazonaws... ║
║  ✅ Frontend ECR: 123456789012.dkr.ecr.ap-south-1.amazonaws... ║
╚══════════════════════════════════════════════════════════════════╝
                              ↓
╔══════════════════════════════════════════════════════════════════╗
║  STAGE 3: UNIT TESTS (PARALLEL ⚡)                  ⏱️ ~1-2m  ║
╠══════════════════════════════════════════════════════════════════╣
║  🧪 Runs both test suites SIMULTANEOUSLY:                       ║
║                                                                  ║
║  ┌─── Backend Tests ────────┐  ┌─── Frontend Tests ──────────┐ ║
║  │ cd backend               │  │ cd frontend                 │ ║
║  │ mvn test                 │  │ npm install                  │ ║
║  │                          │  │ npm test -- --passWithNoTests│ ║
║  │ ⚠️ Fails pipeline       │  │      || true                 │ ║
║  │    if tests fail         │  │                              │ ║
║  │                          │  │ ✅ Failures ALLOWED          │ ║
║  │                          │  │    (won't stop pipeline)     │ ║
║  └──────────────────────────┘  └──────────────────────────────┘ ║
║                                                                  ║
║  WHY PARALLEL: Saves ~1 min by running both at once.            ║
║  WHY "|| true" on frontend: Many React projects don't have      ║
║  test suites configured. Without || true, missing tests would   ║
║  fail the entire pipeline.                                      ║
╚══════════════════════════════════════════════════════════════════╝
                              ↓
╔══════════════════════════════════════════════════════════════════╗
║  STAGE 4: BUILD (PARALLEL ⚡)                       ⏱️ ~2-3m  ║
╠══════════════════════════════════════════════════════════════════╣
║  🔨 Compiles both apps SIMULTANEOUSLY:                          ║
║                                                                  ║
║  ┌─── Backend Build ────────┐  ┌─── Frontend Build ──────────┐ ║
║  │ cd backend               │  │ cd frontend                 │ ║
║  │ mvn clean package        │  │ npm install                  │ ║
║  │    -DskipTests           │  │ npm run build                │ ║
║  │                          │  │                              │ ║
║  │ Output:                  │  │ Output:                      │ ║
║  │ target/backend-0.0.1-    │  │ dist/ folder with            │ ║
║  │ SNAPSHOT.jar              │  │ index.html + JS/CSS bundles │ ║
║  └──────────────────────────┘  └──────────────────────────────┘ ║
║                                                                  ║
║  WHY -DskipTests: Tests already ran in Stage 3.                 ║
║  WHY npm install again: Clean install ensures reproducible build║
╚══════════════════════════════════════════════════════════════════╝
                              ↓
╔══════════════════════════════════════════════════════════════════╗
║  STAGE 5: DOCKER BUILD                              ⏱️ ~2-3m   ║
╠══════════════════════════════════════════════════════════════════╣
║  🐳 Builds Docker images using multi-stage Dockerfiles.         ║
║                                                                  ║
║  Commands:                                                      ║
║  cd backend                                                     ║
║  docker build -t <ECR_BACKEND>:7 -t <ECR_BACKEND>:latest .     ║
║                                                                  ║
║  cd frontend                                                    ║
║  docker build -t <ECR_FRONTEND>:7 -t <ECR_FRONTEND>:latest .   ║
║                                                                  ║
║  TWO TAGS per image:                                            ║
║  • BUILD_NUMBER (e.g., "7") → for traceability / rollback      ║
║  • "latest" → convenience tag for manual kubectl pulls          ║
║                                                                  ║
║  Backend Dockerfile (multi-stage):                              ║
║  Stage 1: maven:3.9.6-eclipse-temurin-17 → builds JAR          ║
║  Stage 2: eclipse-temurin:17-jre-alpine → runs JAR              ║
║           + non-root user (appuser:1001)                        ║
║           + HEALTHCHECK on /actuator/health                     ║
║           + JVM flags: -XX:MaxRAMPercentage=75.0 -XX:+UseG1GC  ║
║                                                                  ║
║  Frontend Dockerfile (multi-stage):                             ║
║  Stage 1: node:20-alpine → npm build → dist/                   ║
║  Stage 2: nginx:alpine → serves dist/                           ║
║           + Security headers (X-Frame-Options, etc.)            ║
║           + SPA routing (try_files → index.html)                ║
║           + Gzip compression                                    ║
║           + HEALTHCHECK on /health                              ║
╚══════════════════════════════════════════════════════════════════╝
                              ↓
╔══════════════════════════════════════════════════════════════════╗
║  STAGE 6: SECURITY SCAN (Trivy)                     ⏱️ ~1-2m   ║
╠══════════════════════════════════════════════════════════════════╣
║  🔍 Scans both Docker images for CRITICAL vulnerabilities.      ║
║                                                                  ║
║  Commands:                                                      ║
║  trivy image --exit-code 1 --severity CRITICAL <backend>:7      ║
║  trivy image --exit-code 1 --severity CRITICAL <frontend>:7     ║
║                                                                  ║
║  BEHAVIOR:                                                      ║
║  • If CRITICAL vulns found → Build marked UNSTABLE (⚠️ yellow) ║
║    but pipeline CONTINUES (does NOT stop)                       ║
║  • If no CRITICAL vulns → ✅ Passed                             ║
║                                                                  ║
║  WHY SOFT-FAIL: In production, you might want to fail hard.    ║
║  We use soft-fail here so new CVEs in base images don't block   ║
║  every deploy while the team investigates fixes.                ║
║                                                                  ║
║  Console Output:                                                ║
║  > Total: 0 (CRITICAL: 0)                                      ║
║  > ✅ Backend image passed security scan.                       ║
║  > ✅ Frontend image passed security scan.                      ║
╚══════════════════════════════════════════════════════════════════╝
                              ↓
╔══════════════════════════════════════════════════════════════════╗
║  STAGE 7: PUSH TO ECR                               ⏱️ ~1-2m   ║
╠══════════════════════════════════════════════════════════════════╣
║  📤 Authenticates with ECR and pushes all 4 image tags.         ║
║                                                                  ║
║  Uses credential: 'aws-credentials'                             ║
║                                                                  ║
║  Commands:                                                      ║
║  1. aws ecr get-login-password --region ap-south-1 | \          ║
║     docker login --username AWS --password-stdin \              ║
║     123456789012.dkr.ecr.ap-south-1.amazonaws.com               ║
║                                                                  ║
║  2. docker push <ECR>/dcmusic-backend:7                         ║
║  3. docker push <ECR>/dcmusic-backend:latest                    ║
║  4. docker push <ECR>/dcmusic-frontend:7                        ║
║  5. docker push <ECR>/dcmusic-frontend:latest                   ║
║                                                                  ║
║  Console Output:                                                ║
║  > Login Succeeded                                              ║
║  > The push refers to repository [...dcmusic-backend]           ║
║  > 7: digest: sha256:xxxx size: 2345                            ║
║  > latest: digest: sha256:xxxx size: 2345                       ║
║  > ✅ All images pushed to ECR!                                 ║
╚══════════════════════════════════════════════════════════════════╝
                              ↓
╔══════════════════════════════════════════════════════════════════╗
║  STAGE 8: UPDATE K8S MANIFESTS                         ⏱️ ~5s  ║
╠══════════════════════════════════════════════════════════════════╣
║  📝 Updates image tags in Helm values for version tracking.     ║
║                                                                  ║
║  Commands:                                                      ║
║  # Update tag in values.yaml: tag: "6" → tag: "7"              ║
║  sed -i 's|tag: ".*"|tag: "7"|g' helm/dcmusic/values.yaml      ║
║                                                                  ║
║  # Also update gitops manifests if they exist                   ║
║  sed -i 's|tag: ".*"|tag: "7"|g' gitops/apps/*.yaml            ║
║                                                                  ║
║  WHY THIS STAGE:                                                ║
║  • If you use ArgoCD, it watches these files and auto-syncs     ║
║  • Even without ArgoCD, it keeps values.yaml in sync with      ║
║    what's actually deployed                                     ║
╚══════════════════════════════════════════════════════════════════╝
                              ↓
╔══════════════════════════════════════════════════════════════════╗
║  STAGE 9: DEPLOY TO EKS                            ⏱️ ~2-5m    ║
╠══════════════════════════════════════════════════════════════════╣
║  🚀 Deploys the app to EKS using Helm (with kubectl fallback). ║
║                                                                  ║
║  Uses credentials: 'aws-credentials' + 'rds-password'          ║
║                                                                  ║
║  Step 1: Configure kubectl                                      ║
║  aws eks update-kubeconfig --name dcmusic-eks --region ap-south-1║
║                                                                  ║
║  Step 2: PRIMARY — Helm upgrade                                 ║
║  helm upgrade --install dcmusic helm/dcmusic \                   ║
║    --namespace dcmusic --create-namespace \                      ║
║    --set backend.image.repository=<ECR_BACKEND> \               ║
║    --set backend.image.tag=7 \                                  ║
║    --set frontend.image.repository=<ECR_FRONTEND> \             ║
║    --set frontend.image.tag=7 \                                 ║
║    --set backend.env.DB_PASSWORD=<rds-password> \               ║
║    --wait --timeout 300s                                        ║
║                                                                  ║
║  Helm creates/updates these Kubernetes resources:               ║
║  • Namespace: dcmusic                                           ║
║  • ServiceAccount: dcmusic-sa                                   ║
║  • Backend: Deployment (2 replicas) + Service + HPA + ConfigMap ║
║  • Frontend: Deployment (2 replicas) + Service + HPA + ConfigMap║
║  • Backend Secret (DB credentials)                              ║
║  • Ingress (ALB, internet-facing, HTTP port 80)                 ║
║  • PodDisruptionBudgets                                         ║
║                                                                  ║
║  Step 3: FALLBACK (if Helm fails)                               ║
║  kubectl set image deployment/dcmusic-backend \                  ║
║    dcmusic-backend=<ECR_BACKEND>:7 -n dcmusic                   ║
║  kubectl set image deployment/dcmusic-frontend \                 ║
║    dcmusic-frontend=<ECR_FRONTEND>:7 -n dcmusic                 ║
║                                                                  ║
║  Console Output:                                                ║
║  > Release "dcmusic" has been upgraded. Happy Helming! ✅       ║
╚══════════════════════════════════════════════════════════════════╝
                              ↓
╔══════════════════════════════════════════════════════════════════╗
║  STAGE 10: VERIFY DEPLOYMENT                       ⏱️ ~30s-5m  ║
╠══════════════════════════════════════════════════════════════════╣
║  ✅ Waits for all pods to be healthy, then prints status.       ║
║                                                                  ║
║  Commands:                                                      ║
║  kubectl rollout status deployment/dcmusic-backend \             ║
║    -n dcmusic --timeout=300s                                    ║
║  kubectl rollout status deployment/dcmusic-frontend \            ║
║    -n dcmusic --timeout=300s                                    ║
║                                                                  ║
║  kubectl get pods -n dcmusic -o wide                            ║
║  kubectl get svc -n dcmusic                                     ║
║                                                                  ║
║  Console Output:                                                ║
║  > deployment "dcmusic-backend" successfully rolled out ✅      ║
║  > deployment "dcmusic-frontend" successfully rolled out ✅     ║
║  >                                                              ║
║  > NAME                              READY   STATUS    AGE     ║
║  > dcmusic-backend-xxxx-yyyy         1/1     Running   2m      ║
║  > dcmusic-backend-xxxx-zzzz         1/1     Running   2m      ║
║  > dcmusic-frontend-xxxx-aaaa        1/1     Running   2m      ║
║  > dcmusic-frontend-xxxx-bbbb        1/1     Running   2m      ║
╚══════════════════════════════════════════════════════════════════╝
                              ↓
╔══════════════════════════════════════════════════════════════════╗
║  POST-BUILD ACTIONS                                              ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  On SUCCESS ✅:                                                  ║
║  ✅ ========================================                    ║
║  ✅  EKS DEPLOYMENT COMPLETED SUCCESSFULLY!                     ║
║  ✅ ========================================                    ║
║  ✅  Cluster:    dcmusic-eks                                    ║
║  ✅  Namespace:  dcmusic                                        ║
║  ✅  Image Tag:  7                                              ║
║  ✅  Backend:    <ECR>/dcmusic-backend:7                        ║
║  ✅  Frontend:   <ECR>/dcmusic-frontend:7                       ║
║                                                                  ║
║  On FAILURE ❌:                                                  ║
║  ❌ Pipeline failed! Check the logs above for details.          ║
║                                                                  ║
║  ALWAYS (success or failure):                                    ║
║  docker image prune -f                                          ║
║  → Cleans up unused Docker images to save disk space            ║
╚══════════════════════════════════════════════════════════════════╝
```

### 12.5 — Access Your App After Deployment

```bash
# Get the ALB DNS hostname
kubectl get ingress -n dcmusic
# Output:
# NAME               HOSTS   ADDRESS                                        PORTS   AGE
# dcmusic-ingress    *       k8s-dcmusic-xxxx.ap-south-1.elb.amazonaws.com  80      5m

# Open in browser (HTTP only — no DNS/TLS on free tier):
# http://k8s-dcmusic-xxxx.ap-south-1.elb.amazonaws.com
```

---

## 13. Phase 10 — GitHub Webhook Setup (Auto-Trigger)

> This makes the app pipeline trigger automatically every time you push code.

### Step 1: Go to Your GitHub Repository Settings

1. Open `https://github.com/<YOUR_USERNAME>/Prod_DevOps`
2. Click **Settings** tab (top) → **Webhooks** (left sidebar) → **"Add webhook"**

### Step 2: Configure the Webhook

| Field | Value |
|---|---|
| **Payload URL** | `http://<JENKINS_IP>:8080/github-webhook/` ⚠️ *Trailing slash required!* |
| **Content type** | `application/json` |
| **Which events?** | Select **"Just the push event"** |
| **Active** | ✅ Checked |

Click **"Add webhook"**

### Step 3: Verify

- GitHub shows a green ✅ after the first successful ping
- Now every `git push` to `main` triggers the `dcmusic-app` pipeline automatically

> ⚠️ **Note**: If Jenkins is running on your local machine (localhost), GitHub can't reach it. Options:
> - Use [ngrok](https://ngrok.com/) to create a tunnel: `ngrok http 8080`
> - Run Jenkins on an EC2 instance with a public IP
> - Use Jenkins polling instead (less efficient): Check "Poll SCM" with schedule `H/5 * * * *`

---

## 14. Phase 11 — Monitoring Setup (Prometheus + Grafana)

> Optional but recommended. Run AFTER the app is deployed.

```bash
# Use the included install script
chmod +x /home/dc/Desktop/Prod_DevOps/monitoring/install.sh
/home/dc/Desktop/Prod_DevOps/monitoring/install.sh

# Or manually:
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

kubectl create namespace monitoring

helm install prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f /home/dc/Desktop/Prod_DevOps/monitoring/prometheus/values.yaml

# Get Grafana URL
kubectl get svc -n monitoring | grep grafana
# Default credentials: admin / prom-operator

# Apply custom alerting rules
kubectl apply -f /home/dc/Desktop/Prod_DevOps/monitoring/prometheus/alerting-rules.yaml
```

---

## 15. How to Run Each Pipeline — Quick Reference

### Scenario Matrix

| Scenario | Which Pipeline | How to Trigger | Approx Time |
|---|---|---|---|
| **First-time setup** | 1️⃣ `dcmusic-infra` → then 2️⃣ `dcmusic-app` | Manual "Build Now" | ~20m + ~8m |
| **Pushed new code** | `dcmusic-app` only | Automatic (webhook) | ~5-8m |
| **Want to scale nodes** | Edit `terraform/variables.tf` → push → `dcmusic-infra` | Manual "Build Now" | ~5m |
| **Changed Terraform modules** | `dcmusic-infra` | Manual "Build Now" | ~5-15m |
| **Want to destroy everything** | `terraform destroy` locally | NOT a Jenkins job | ~15m |
| **Rollback to previous version** | `dcmusic-app` with older tag | See rollback steps below | ~3m |

### Quick Rollback

```bash
# Rollback to previous Helm release
helm rollback dcmusic 1 -n dcmusic  # "1" = revision number

# Or: Rollback to specific image tag
kubectl set image deployment/dcmusic-backend \
  dcmusic-backend=<ECR>/dcmusic-backend:6 -n dcmusic
kubectl set image deployment/dcmusic-frontend \
  dcmusic-frontend=<ECR>/dcmusic-frontend:6 -n dcmusic
```

### Destroying Infrastructure (Cleanup)

```bash
# ⚠️ This deletes EVERYTHING — EKS, RDS, VPC, etc.
cd /home/dc/Desktop/Prod_DevOps/terraform
terraform destroy -var="db_password=<your-rds-password>"
# Type "yes" when prompted
```

---

## 16. Pipeline File Code Walkthrough — Line by Line

### 16.1 — `Jenkinsfile.infra` Structure

```groovy
// Lines 1-27:  Header comments (purpose, stages, prerequisites)
// Lines 29-39: pipeline → agent any, environment block
//              - AWS_REGION = 'ap-south-1'
//              - PROJECT_NAME = 'dcmusic'
//              - EKS_CLUSTER_NAME = 'dcmusic-eks'
//
// Lines 44-54:   Stage 1: Checkout (checkout scm)
// Lines 63-93:   Stage 2: Terraform Init
//                - withCredentials[aws-credentials]
//                - Gets Account ID via STS
//                - terraform init with -backend-config overrides
// Lines 102-123: Stage 3: Terraform Plan
//                - withCredentials[aws-credentials + rds-password]
//                - terraform plan -var="db_password=..." -out=tfplan
// Lines 132-138: Stage 4: Manual Approval
//                - input message: 'Review terraform plan. Proceed?'
// Lines 147-163: Stage 5: Terraform Apply
//                - terraform apply -auto-approve tfplan
// Lines 172-195: Stage 6: Update Kubeconfig
//                - aws eks update-kubeconfig
//                - Prints instructions for local setup
//
// Lines 198-209: Post actions (success/failure messages)
```

### 16.2 — `Jenkinsfile` Structure

```groovy
// Lines 1-40:    Header comments (10 stages, prerequisites, tools needed)
// Lines 42-60:   pipeline → agent any, tools{maven, nodejs}, environment block
//                - AWS_REGION, PROJECT_NAME, EKS_CLUSTER_NAME
//
// Lines 72-77:     Stage 1: Checkout (checkout scm)
// Lines 86-109:    Stage 2: AWS Setup
//                  - withCredentials[aws-credentials]
//                  - aws sts get-caller-identity → AWS_ACCOUNT_ID
//                  - Constructs ECR_BACKEND, ECR_FRONTEND URLs
// Lines 119-142:   Stage 3: Unit Tests (PARALLEL)
//                  - Backend: mvn test
//                  - Frontend: npm install && npm test || true
// Lines 151-174:   Stage 4: Build (PARALLEL)
//                  - Backend: mvn clean package -DskipTests
//                  - Frontend: npm install + npm run build
// Lines 183-197:   Stage 5: Docker Build
//                  - docker build with BUILD_NUMBER + latest tags
// Lines 207-237:   Stage 6: Security Scan
//                  - trivy image --exit-code 1 --severity CRITICAL
//                  - Soft fail: unstable() not error()
// Lines 245-270:   Stage 7: Push to ECR
//                  - aws ecr get-login-password | docker login
//                  - docker push × 4 (backend:N, backend:latest, frontend:N, frontend:latest)
// Lines 281-306:   Stage 8: Update K8s Manifests
//                  - sed -i to update tag in values.yaml
// Lines 315-363:   Stage 9: Deploy to EKS
//                  - aws eks update-kubeconfig
//                  - helm upgrade --install (primary)
//                  - kubectl set image (fallback)
// Lines 371-391:   Stage 10: Verify Deployment
//                  - kubectl rollout status (both deployments)
//                  - kubectl get pods + svc
//
// Lines 396-418:  Post actions
//                 - success: prints deployment summary
//                 - failure: error message
//                 - always: docker image prune -f
```

---

## 17. Troubleshooting Guide

### ❌ `docker: permission denied while trying to connect to the Docker daemon`

```bash
# Fix: Add jenkins to docker group
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
# Then re-run the build
```

### ❌ `aws: command not found` or `terraform: command not found`

```bash
# Fix: Tools not in Jenkins PATH. Create symlinks:
sudo ln -sf /usr/local/bin/aws /usr/bin/aws
sudo ln -sf /usr/local/bin/terraform /usr/bin/terraform
sudo ln -sf /usr/local/bin/kubectl /usr/bin/kubectl
sudo ln -sf /usr/local/bin/helm /usr/bin/helm
sudo ln -sf /usr/local/bin/trivy /usr/bin/trivy

# Or add to Jenkins: Manage Jenkins → System → Environment variables
# Name: PATH   Value: /usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
```

### ❌ `Tool type "maven" does not have an install of "Maven-3.9"` configured

```bash
# Fix: The name in Jenkins Global Tool Configuration doesn't match the Jenkinsfile.
# Go to: Manage Jenkins → Tools → Maven
# Ensure name is EXACTLY: Maven-3.9  (case-sensitive, hyphen not space)
# Same for NodeJS: Node-20
```

### ❌ `Error: No credentials found for id "aws-credentials"`

```bash
# Fix: Credential ID doesn't match what's in the Jenkinsfile
# Go to: Manage Jenkins → Credentials → System → Global
# Ensure ID is EXACTLY: aws-credentials (lowercase, hyphen)
# Also verify: rds-password (for Stage 9 of app pipeline)
```

### ❌ S3 backend error: `bucket does not exist`

```bash
# Fix: Create the S3 bucket (Phase 6)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3 mb s3://dcmusic-tf-state-${AWS_ACCOUNT_ID} --region ap-south-1
```

### ❌ `error: You must be logged in to the server (Unauthorized)` on kubectl

```bash
# Fix: Jenkins IAM user needs EKS access.
# If you created EKS with a DIFFERENT IAM user than Jenkins uses:

kubectl edit configmap aws-auth -n kube-system
# Add under mapUsers:
#   - userarn: arn:aws:iam::XXXX:user/jenkins-user
#     username: jenkins-user
#     groups:
#       - system:masters
```

### ❌ Stage 4 (Manual Approval) — "Where is the approval button?"

```
Pipeline is paused. Find the button at:
→ Jenkins Dashboard → dcmusic-infra → Build #N
→ Look for "Paused for Input" link
→ Or: Console Output → scroll to very bottom → click "Apply"/"Abort"
→ Or: Stage View → the blue/pulsing "Manual Approval" stage box → click it
```

### ❌ Helm upgrade fails with "UPGRADE FAILED: release not found"

```bash
# This happens on first deploy. The --install flag in our Jenkinsfile handles it,
# but if it still fails, manually install once:
cd /home/dc/Desktop/Prod_DevOps
helm upgrade --install dcmusic helm/dcmusic \
  -n dcmusic --create-namespace \
  --set backend.image.tag=latest \
  --set frontend.image.tag=latest
# Then subsequent Jenkins builds will succeed with helm upgrade
```

### ❌ ECR push fails with "no basic auth credentials"

```
# Fix: ECR login token expired (they last 12 hours).
# The Jenkinsfile re-authenticates every run, so this usually means
# the aws-credentials in Jenkins are wrong or the IAM user lacks
# ecr:GetAuthorizationToken permission.
# Go to: Manage Jenkins → Credentials → aws-credentials → Update
```

### ❌ Build takes too long or runs out of disk space

```bash
# Clean up Docker on Jenkins server
sudo -u jenkins docker system prune -af --volumes

# Check disk usage
df -h

# The Jenkinsfile already runs "docker image prune -f" after every build,
# but doesn't remove ALL unused images. Run the above for deep cleanup.
```

### ❌ EKS nodes show "NotReady" status

```bash
# Check node status
kubectl get nodes
kubectl describe node <node-name>

# Common cause: VPC-CNI plugin not installed
# Our Terraform installs it as an EKS addon, but verify:
kubectl get pods -n kube-system | grep aws-node
# Should show: aws-node-xxxxx   1/1   Running
```

### ❌ ALB Ingress not creating a Load Balancer

```bash
# Verify ALB controller is running
kubectl get pods -n kube-system | grep aws-load-balancer
# If not running → Re-do Phase 8, Step 11.1

# Check ingress status
kubectl describe ingress -n dcmusic
# Look for Events section — it shows errors from the ALB controller

# Common fix: Subnet tagging issue
# Our Terraform tags subnets with:
#   kubernetes.io/role/elb = 1 (public subnets)
#   kubernetes.io/role/internal-elb = 1 (private subnets)
```

---

## 18. Complete Command Cheat Sheet

### Before Any Pipeline

```bash
# Verify AWS credentials work
aws sts get-caller-identity

# Verify Jenkins is running
sudo systemctl status jenkins

# Check all tools
sudo -u jenkins bash -c 'docker --version; aws --version; terraform -version; kubectl version --client; helm version --short; trivy --version'
```

### During/After Infrastructure Pipeline

```bash
# Check Terraform state
cd /home/dc/Desktop/Prod_DevOps/terraform
terraform show               # Current state
terraform output             # All output values
terraform state list         # List all managed resources

# Connect to EKS
aws eks update-kubeconfig --name dcmusic-eks --region ap-south-1
kubectl get nodes
kubectl cluster-info
```

### During/After App Pipeline

```bash
# Check deployments
kubectl get all -n dcmusic
kubectl get pods -n dcmusic -o wide
kubectl get svc -n dcmusic
kubectl get ingress -n dcmusic

# View pod logs
kubectl logs -f deployment/dcmusic-backend -n dcmusic
kubectl logs -f deployment/dcmusic-frontend -n dcmusic

# Check Helm releases
helm list -n dcmusic
helm history dcmusic -n dcmusic

# Check ECR images
aws ecr list-images --repository-name dcmusic-backend --region ap-south-1
aws ecr list-images --repository-name dcmusic-frontend --region ap-south-1
```

### Emergency Commands

```bash
# Rollback Helm release to previous version
helm rollback dcmusic 0 -n dcmusic

# Restart all pods (rolling restart)
kubectl rollout restart deployment/dcmusic-backend -n dcmusic
kubectl rollout restart deployment/dcmusic-frontend -n dcmusic

# Scale replicas manually
kubectl scale deployment/dcmusic-backend --replicas=3 -n dcmusic

# Delete and redeploy
helm uninstall dcmusic -n dcmusic
# Then re-run dcmusic-app pipeline from Jenkins

# Nuclear option: Destroy all infrastructure
cd /home/dc/Desktop/Prod_DevOps/terraform
terraform destroy -var="db_password=<your-password>"
```

---

*Generated for DC Music — Production DevOps on AWS EKS*
*Pipeline Files: `Jenkinsfile` (10-stage CI/CD) + `Jenkinsfile.infra` (6-stage Infrastructure)*
*Region: ap-south-1 | Cluster: dcmusic-eks | No DNS/TLS (Free Tier — HTTP via ALB DNS)*
