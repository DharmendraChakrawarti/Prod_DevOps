# 🚀 EC2 Jumper (Bastion) Setup Guide for Amazon EKS

This guide explains how to create, configure, and connect to a dedicated **EC2 Jumper / Bastion Host** to manage and control your **DCMusic Amazon EKS cluster** (`dcmusic-eks`) securely.

---

## 📋 Architecture & Purpose

The worker nodes and RDS database run in **private subnets** with no direct internet ingress. The Jumper Host is deployed in a **public subnet** of the same VPC to act as the administrative entry point for running `kubectl`, `helm`, deployment scripts, and debugging commands.

```
Administrator (Laptop)
       │
       │ SSH (Port 22)
       ▼
┌────────────────────────────────────────────────────────┐
│ VPC: dcmusic-dev-vpc (10.0.0.0/16)                    │
│                                                        │
│   PUBLIC SUBNET (10.0.1.0/24)                          │
│   ┌────────────────────────────────────────────────┐   │
│   │  EC2 Jumper Host (dcmusic-eks-jumper)          │   │
│   │  • AWS CLI v2                                  │   │
│   │  • kubectl (v1.35)                             │   │
│   │  • Helm v3                                     │   │
│   │  • Git                                         │   │
│   └───────────────────────┬────────────────────────┘   │
│                           │                             │
│                           │ Cluster API & Nodes        │
│                           ▼                             │
│   PRIVATE SUBNETS (10.0.10.0/24 & 10.0.11.0/24)        │
│   ┌────────────────────────────────────────────────┐   │
│   │  EKS Managed Worker Nodes (AL2023)             │   │
│   │  RDS MySQL 8.0 (db.t3.micro)                   │   │
│   └────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────┘
```

---

## 🛠️ Launch Specifications

| Property | Value | Notes |
|---|---|---|
| **Instance Name** | `dcmusic-eks-jumper` | Helps identify in EC2 Console |
| **Region** | `ap-south-1` (Mumbai) | Same region as EKS & RDS |
| **AMI** | `Ubuntu Server 22.04 LTS` (or `AL2023`) | Free-tier eligible |
| **Instance Type** | `t3.micro` or `t3.small` | 1-2 vCPU, 1-2 GB RAM |
| **VPC** | `dcmusic-dev-vpc` | Must be inside the project VPC |
| **Subnet** | Public Subnet 1 (`10.0.1.0/24`) | Needs public internet route table |
| **Auto-assign Public IP** | **Enabled** | Required for SSH access |
| **Security Group** | Inbound SSH (Port 22) from My IP | Restrict to your IP address |

---

## 🚀 Step 1: Launch via AWS Management Console

1. Navigate to **EC2 Console** → Click **Launch instances**.
2. **Name**: `dcmusic-eks-jumper`
3. **Application and OS Images**: Choose **Ubuntu Server 22.04 LTS (HVM)**.
4. **Instance type**: `t3.micro` (or `t3.small`).
5. **Key pair**: Select your SSH key pair (or create a new `.pem` key).
6. **Network Settings** (Click **Edit**):
   - **VPC**: Select `dcmusic-dev-vpc`.
   - **Subnet**: Select `dcmusic-dev-public-subnet-1` (or any public subnet).
   - **Auto-assign public IP**: **Enable** *(Crucial)*.
   - **Firewall (Security Groups)**:
     - Select **Create security group**.
     - Security group name: `dcmusic-jumper-sg`.
     - Inbound rule: Type = `SSH`, Port = `22`, Source = `My IP` (or `0.0.0.0/0`).
7. **Advanced Details** → Scroll to **User data** and paste the automated install script:

```bash
#!/bin/bash
set -e

# Update and install dependencies
apt-get update -y
apt-get install -y curl unzip git apt-transport-https ca-certificates gnupg jq

# 1. Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# 2. Install kubectl
K8S_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/kubectl"
chmod +x ./kubectl
mv ./kubectl /usr/local/bin/kubectl

# 3. Install Helm 3
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "✅ Jumper host initialization complete!"
```

8. Click **Launch instance**.

---

## 🔑 Step 2: SSH Connection & EKS Authentication

1. Open your local terminal and connect via SSH:
   ```bash
   chmod 400 your-key.pem
   ssh -i your-key.pem ubuntu@<EC2-PUBLIC-IP>
   ```

2. Configure AWS credentials (use credentials for `dcmusic-admin`):
   ```bash
   aws configure
   ```
   - **AWS Access Key ID**: `[Your Access Key]`
   - **AWS Secret Access Key**: `[Your Secret Key]`
   - **Default region name**: `ap-south-1`
   - **Default output format**: `json`

3. Connect `kubectl` to your EKS cluster:
   ```bash
   aws eks update-kubeconfig --name dcmusic-eks --region ap-south-1
   ```

4. Verify cluster connectivity:
   ```bash
   kubectl get nodes
   ```
   *Expected Output:*
   ```text
   NAME                                                STATUS   ROLES    AGE   VERSION
   ip-10-0-10-xxx.ap-south-1.compute.internal          Ready    <none>   1d    v1.35.x
   ip-10-0-11-xxx.ap-south-1.compute.internal          Ready    <none>   1d    v1.35.x
   ```

---

## 📦 Step 3: Clone Project & Run Operations

1. Clone the repository directly to your Jumper host:
   ```bash
   git clone https://github.com/DharmendraChakrawarti/Prod_DevOps.git
   cd Prod_DevOps
   ```

2. Run common operations directly from the jumper:
   - **Install Monitoring (Prometheus + Grafana)**:
     ```bash
     chmod +x monitoring/install.sh
     ./monitoring/install.sh
     ```
   - **Install ArgoCD (GitOps)**:
     ```bash
     chmod +x gitops/argocd/install.sh
     ./gitops/argocd/install.sh
     ```
   - **Inspect Pods & Logs**:
     ```bash
     kubectl get pods -n dcmusic
     kubectl logs -n dcmusic -l app.kubernetes.io/component=backend --tail=50
     ```

---

## 🌐 Alternative: Launching the Jumper in ANOTHER AWS Account (Cross-Account Setup)

If you want to run the Jumper host in a completely separate AWS Account (e.g. Account B) to control the EKS cluster in the primary project account (Account A: `328159054985`), follow this section.

Because our EKS cluster has **Public API Access Enabled** (`endpoint_public_access = true`) and modern **API Access Entries** (`authentication_mode = "API_AND_CONFIG_MAP"`), no VPC peering or complex transit gateways are required.

```
┌──────────────────────────────────────────────┐        ┌──────────────────────────────────────────────┐
│ AWS ACCOUNT B (Management / Jumper Account)  │        │ AWS ACCOUNT A (328159054985 - EKS Project)   │
│                                              │        │                                              │
│   Default VPC / Public Subnet                │        │   dcmusic-dev-vpc (10.0.0.0/16)              │
│   ┌──────────────────────────────────────┐   │        │   ┌──────────────────────────────────────┐   │
│   │  EC2 Jumper Host                     │   │ HTTPS  │   │  EKS Cluster: dcmusic-eks            │   │
│   │  • aws cli, kubectl, helm, git       │───┼────────┼──▶│  • Public API Endpoint Enabled       │   │
│   │  • Configured with Account A access  │   │ Port   │   │  • Access Entry:                     │   │
│   └──────────────────────────────────────┘   │  443   │   │    Allows Account B Principal        │   │
│                                              │        │   └──────────────────────────────────────┘   │
└──────────────────────────────────────────────┘        └──────────────────────────────────────────────┘
```

### Option A: Use Account A Credentials on Account B Jumper (Fastest)

1. Launch your EC2 instance in **Account B** (in any default public subnet with auto-assign public IP enabled, and paste the User Data script from Step 1).
2. SSH into the Jumper in Account B:
   ```bash
   ssh -i your-account-b-key.pem ubuntu@<ACCOUNT_B_JUMPER_PUBLIC_IP>
   ```
3. Run `aws configure` and supply the access keys of the `dcmusic-admin` user from **Account A**:
   ```bash
   aws configure
   # AWS Access Key ID: [Access Key from Account A]
   # AWS Secret Access Key: [Secret Key from Account A]
   # Default region name: ap-south-1
   # Default output format: json
   ```
4. Update kubeconfig targeting Account A's cluster:
   ```bash
   aws eks update-kubeconfig --name dcmusic-eks --region ap-south-1
   ```
5. Verify access:
   ```bash
   kubectl get nodes
   ```

---

### Option B: Cross-Account IAM Role via EKS Access Entry (Enterprise Best Practice)

If you do NOT want to store static access keys on the instance and prefer IAM Roles:

1. **In Account B**:
   - Create an IAM Role for the EC2 Jumper (e.g., `EKSJumperRole`).
   - Attach this IAM role to your Jumper EC2 instance profile.
   - Note down the Role ARN: `arn:aws:iam::<ACCOUNT_B_ID>:role/EKSJumperRole`.

2. **In Account A (Where EKS lives)**:
   - Go to **AWS Console** → **EKS** → Clusters → `dcmusic-eks` → **Access** tab.
   - Under **IAM access entries**, click **Create access entry**.
   - **IAM principal ARN**: Enter Account B's role ARN:
     ```text
     arn:aws:iam::<ACCOUNT_B_ID>:role/EKSJumperRole
     ```
   - Click **Next** → Click **Add access policy**:
     - Policy: **`AmazonEKSClusterAdminPolicy`**
     - Access scope: **Cluster**
   - Click **Create**.

3. **On the Jumper in Account B**:
   - Update kubeconfig:
     ```bash
     aws eks update-kubeconfig --name dcmusic-eks --region ap-south-1
     ```
   - Run `kubectl get nodes` — the jumper authenticates through AWS STS cross-account token exchange seamlessly!

---

## ⚠️ Important Teardown Note

When you eventually tear down the infrastructure using `Jenkinsfile.infra.delete` or `terraform destroy`:
- **If your Jumper is in Account A's VPC**: You must terminate it FIRST so the public subnet can be deleted (see [Issue 11 in troubleshoot.md](file:///home/dc/Desktop/Prod_DevOps/Documentation/troubleshoot.md)).
- **If your Jumper is in Account B**: It does not block Account A's VPC teardown at all! You can keep it running without any conflict.

