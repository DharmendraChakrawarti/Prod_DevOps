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

## ⚠️ Important Teardown Note

When you eventually tear down the infrastructure using `Jenkinsfile.infra.delete` or `terraform destroy`:
- **You must terminate this manual Jumper EC2 instance FIRST!**
- If an active EC2 instance is attached to the VPC public subnet, AWS will prevent Terraform from deleting the subnet and Internet Gateway (see [Issue 11 in troubleshoot.md](file:///home/dc/Desktop/Prod_DevOps/Documentation/troubleshoot.md)).
