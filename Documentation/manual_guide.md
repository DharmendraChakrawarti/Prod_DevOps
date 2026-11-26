# 📋 Manual AWS Infrastructure Creation Guide (AWS Management Console)

> **Complete Step-by-Step UI Guide for DC Music**  
> Everything created manually through the AWS Portal without running Terraform.  
> Target Region: **`ap-south-1` (Mumbai)** | Cluster: **`dcmusic-eks`** | Project: **`dcmusic`**

---

## 📑 Table of Contents
1. [Prerequisites & Architecture Mapping](#1-prerequisites--architecture-mapping)
2. [Step 1: IAM Roles & Policies (Cluster & Node Roles)](#step-1-iam-roles--policies)
3. [Step 2: VPC, Subnets, Internet Gateway & NAT Gateway](#step-2-vpc-subnets-igw-and-nat-gateway)
4. [Step 3: Security Groups (Cluster, Nodes, RDS)](#step-3-security-groups)
5. [Step 4: ECR Repositories (Backend & Frontend)](#step-4-ecr-repositories)
6. [Step 5: RDS MySQL Database (Free Tier)](#step-5-rds-mysql-database)
7. [Step 6: EKS Cluster Creation](#step-6-eks-cluster-creation)
8. [Step 7: EKS Managed Node Group](#step-7-eks-managed-node-group)
9. [Step 8: EKS Add-ons & Local Kubeconfig Connection](#step-8-eks-add-ons--local-kubeconfig-connection)
10. [Step 9: IAM OIDC Provider & AWS Load Balancer Controller Role](#step-9-iam-oidc-provider--alb-controller-role)
11. [Step 10: Deploy AWS Load Balancer Controller](#step-10-deploy-aws-load-balancer-controller)
12. [Step 11: Connect Jenkins & App Pipeline](#step-11-connect-jenkins--app-pipeline)
13. [Resource Summary & Checklist](#resource-summary--checklist)

---

## 1. Prerequisites & Architecture Mapping

Make sure you are logged into the AWS Console:
- **Region Dropdown (Top Right)**: Select **`Asia Pacific (Mumbai) ap-south-1`**. Stay in this region for all steps!
- Keep a notepad handy to record IDs:
  - `VPC ID`
  - `Subnet IDs` (2 Public, 2 Private)
  - `Security Group IDs` (EKS Cluster, Nodes, RDS)
  - `RDS Endpoint`
  - `AWS Account ID` (Top right corner, 12-digit number)

---

## Step 1: IAM Roles & Policies

Before creating network or compute, create the 2 foundational IAM roles.

### 1.1 EKS Cluster IAM Role (`dcmusic-dev-eks-cluster-role`)
1. Go to **IAM Console** (`https://console.aws.amazon.com/iam/`).
2. In left navigation, click **Roles** → Click **Create role**.
3. **Trusted entity type**: Select **AWS service**.
4. **Use case**: In the dropdown, select **EKS** → select **EKS - Cluster** (or select EKS and radio button for *EKS - Cluster*).
5. Click **Next**.
6. **Add permissions**:
   - Ensure `AmazonEKSClusterPolicy` is checked.
7. Click **Next**.
8. **Role name**: `dcmusic-dev-eks-cluster-role`
9. **Tags**:
   - Key: `Project`, Value: `dcmusic`
   - Key: `Environment`, Value: `dev`
10. Click **Create role**.

---

### 1.2 EKS Node Group IAM Role (`dcmusic-dev-eks-nodes-role`)
1. In **Roles**, click **Create role**.
2. **Trusted entity type**: Select **AWS service**.
3. **Use case**: Select **EC2**.
4. Click **Next**.
5. **Add permissions**: Search and check the following 4 policies:
   - ✅ `AmazonEKSWorkerNodePolicy`
   - ✅ `AmazonEKS_CNI_Policy`
   - ✅ `AmazonEC2ContainerRegistryReadOnly`
   - ✅ `AmazonSSMManagedInstanceCore`
6. Click **Next**.
7. **Role name**: `dcmusic-dev-eks-nodes-role`
8. **Tags**:
   - Key: `Project`, Value: `dcmusic`
   - Key: `Environment`, Value: `dev`
9. Click **Create role**.

---

## Step 2: VPC, Subnets, IGW, and NAT Gateway

### 2.1 Create the VPC
1. Go to **VPC Console** (`ap-south-1`).
2. Click **VPCs** → Click **Create VPC**.
3. Settings:
   - **Resources to create**: Select **VPC only**
   - **Name tag**: `dcmusic-dev-vpc`
   - **IPv4 CIDR manual input**: `10.0.0.0/16`
   - **IPv6 CIDR block**: No IPv6 CIDR block
   - **Tenancy**: Default
4. Click **Create VPC**.
5. Once created, select `dcmusic-dev-vpc` → **Actions** → **Edit VPC settings**:
   - ✅ Check **Enable DNS resolution**
   - ✅ Check **Enable DNS hostnames**
   - Click **Save changes**.

---

### 2.2 Create 4 Subnets (2 Public + 2 Private)
Click **Subnets** in the left menu → Click **Create subnet**:
Select VPC: `dcmusic-dev-vpc`.

Create each subnet with the settings below:

#### Subnet 1: Public Subnet 1
- **Subnet name**: `dcmusic-dev-public-1`
- **Availability Zone**: `ap-south-1a`
- **IPv4 CIDR block**: `10.0.1.0/24`

#### Subnet 2: Public Subnet 2 (Click "Add new subnet")
- **Subnet name**: `dcmusic-dev-public-2`
- **Availability Zone**: `ap-south-1b`
- **IPv4 CIDR block**: `10.0.2.0/24`

#### Subnet 3: Private Subnet 1 (Click "Add new subnet")
- **Subnet name**: `dcmusic-dev-private-1`
- **Availability Zone**: `ap-south-1a`
- **IPv4 CIDR block**: `10.0.10.0/24`

#### Subnet 4: Private Subnet 2 (Click "Add new subnet")
- **Subnet name**: `dcmusic-dev-private-2`
- **Availability Zone**: `ap-south-1b`
- **IPv4 CIDR block**: `10.0.11.0/24`

Click **Create subnet**.

#### Enable Auto-Assign Public IP for Public Subnets:
1. Select `dcmusic-dev-public-1` → **Actions** → **Edit subnet settings**.
   - Check **Enable auto-assign public IPv4 address** → Click **Save**.
2. Select `dcmusic-dev-public-2` → **Actions** → **Edit subnet settings**.
   - Check **Enable auto-assign public IPv4 address** → Click **Save**.

#### ⚠️ CRITICAL: Add Kubernetes Discovery Tags to Subnets
Kubernetes AWS Load Balancer Controller relies on these tags:
1. Select `dcmusic-dev-public-1` and `dcmusic-dev-public-2` (one by one) → **Tags** tab → **Manage tags** → Add:
   - Key: `kubernetes.io/role/elb` | Value: `1`
   - Key: `kubernetes.io/cluster/dcmusic-eks` | Value: `shared`
2. Select `dcmusic-dev-private-1` and `dcmusic-dev-private-2` (one by one) → **Tags** tab → **Manage tags** → Add:
   - Key: `kubernetes.io/role/internal-elb` | Value: `1`
   - Key: `kubernetes.io/cluster/dcmusic-eks` | Value: `shared`

---

### 2.3 Internet Gateway (IGW)
1. Go to **Internet Gateways** → Click **Create internet gateway**.
2. **Name tag**: `dcmusic-dev-igw` → Click **Create internet gateway**.
3. Select `dcmusic-dev-igw` → Click **Actions** → **Attach to VPC**.
4. Choose `dcmusic-dev-vpc` → Click **Attach internet gateway**.

---

### 2.4 Elastic IP & NAT Gateway
1. Go to **Elastic IPs** → Click **Allocate Elastic IP address**.
   - **Tags**: Key: `Name`, Value: `dcmusic-dev-nat-eip`
   - Click **Allocate**.
2. Go to **NAT Gateways** → Click **Create NAT gateway**.
   - **Name**: `dcmusic-dev-nat`
   - **Subnet**: Select `dcmusic-dev-public-1`
   - **Connectivity type**: **Public**
   - **Elastic IP allocation ID**: Select the EIP created above (`dcmusic-dev-nat-eip`)
   - Click **Create NAT gateway**.  
   *(Wait ~2-3 minutes for status to change from Pending to Available).*

---

### 2.5 Route Tables & Associations

#### Public Route Table:
1. Go to **Route Tables** → Click **Create route table**.
   - **Name**: `dcmusic-dev-public-rt`
   - **VPC**: `dcmusic-dev-vpc`
   - Click **Create route table**.
2. Select `dcmusic-dev-public-rt` → **Routes** tab → **Edit routes**:
   - Click **Add route**:
     - Destination: `0.0.0.0/0`
     - Target: Select **Internet Gateway** → select `dcmusic-dev-igw`
   - Click **Save changes**.
3. Click **Subnet associations** tab → **Edit subnet associations**:
   - Check `dcmusic-dev-public-1` and `dcmusic-dev-public-2`.
   - Click **Save associations**.

#### Private Route Table:
1. Click **Create route table**:
   - **Name**: `dcmusic-dev-private-rt`
   - **VPC**: `dcmusic-dev-vpc`
   - Click **Create route table**.
2. Select `dcmusic-dev-private-rt` → **Routes** tab → **Edit routes**:
   - Click **Add route**:
     - Destination: `0.0.0.0/0`
     - Target: Select **NAT Gateway** → select `dcmusic-dev-nat`
   - Click **Save changes**.
3. Click **Subnet associations** tab → **Edit subnet associations**:
   - Check `dcmusic-dev-private-1` and `dcmusic-dev-private-2`.
   - Click **Save associations**.

---

## Step 3: Security Groups

Create 3 security groups in `dcmusic-dev-vpc`.

### 3.1 EKS Cluster Security Group (`dcmusic-dev-eks-cluster-sg`)
1. Go to **VPC Console** → **Security Groups** → Click **Create security group**.
2. **Security group name**: `dcmusic-dev-eks-cluster-sg`
3. **Description**: `Security group for EKS cluster API server`
4. **VPC**: Select `dcmusic-dev-vpc`.
5. **Inbound rules**:
   - Type: `HTTPS` | Port: `443` | Source: `Custom` → `10.0.0.0/16`
6. Click **Create security group**. (Note down its ID, e.g. `sg-cluster123`).

---

### 3.2 EKS Node Security Group (`dcmusic-dev-eks-nodes-sg`)
1. Click **Create security group**.
2. **Security group name**: `dcmusic-dev-eks-nodes-sg`
3. **Description**: `Security group for EKS worker nodes`
4. **VPC**: Select `dcmusic-dev-vpc`.
5. **Inbound rules**:
   - Rule 1: Type: `All traffic` | Protocol: `All` | Port: `All` | Source: `Custom` → select `dcmusic-dev-eks-cluster-sg`
   - Rule 2: Type: `Custom TCP` | Port: `10250` | Source: `Custom` → `10.0.0.0/16` (Kubelet API)
   - Rule 3: Type: `Custom TCP` | Port: `30000 - 32767` | Source: `Anywhere-IPv4` (`0.0.0.0/0`) (NodePorts)
6. Click **Create security group**. (Note down its ID, e.g. `sg-node123`).

#### Add Self-Referencing Rule & Cross-Rule:
1. Select `dcmusic-dev-eks-nodes-sg` → **Edit inbound rules** → **Add rule**:
   - Type: `All traffic` | Port: `All` | Source: `Custom` → Select `dcmusic-dev-eks-nodes-sg` (self)
   - Click **Save rules**.
2. Select `dcmusic-dev-eks-cluster-sg` → **Edit inbound rules** → **Add rule**:
   - Type: `HTTPS` | Port: `443` | Source: `Custom` → Select `dcmusic-dev-eks-nodes-sg`
   - Click **Save rules**.

---

### 3.3 RDS Security Group (`dcmusic-dev-rds-sg`)
1. Click **Create security group**.
2. **Security group name**: `dcmusic-dev-rds-sg`
3. **Description**: `Security group for RDS MySQL`
4. **VPC**: Select `dcmusic-dev-vpc`.
5. **Inbound rules**:
   - Type: `MySQL/Aurora` | Port: `3306` | Source: `Custom` → Select `dcmusic-dev-eks-nodes-sg`
6. Click **Create security group**.

---

## Step 4: ECR Repositories

1. Go to **ECR Console** (`https://console.aws.amazon.com/ecr/`).
2. Click **Create repository**.
   - **General settings**: Select **Private**
   - **Repository name**: `dcmusic-backend`
   - **Tag immutability**: Disabled
   - Click **Create repository**.
3. Click **Create repository** again:
   - **General settings**: Select **Private**
   - **Repository name**: `dcmusic-frontend`
   - Click **Create repository**.

---

## Step 5: RDS MySQL Database

### 5.1 Create DB Subnet Group
1. Go to **RDS Console** → Left menu: **Subnet groups** → Click **Create DB subnet group**.
2. Settings:
   - **Name**: `dcmusic-dev-db-subnet`
   - **Description**: `Subnet group for DC Music RDS MySQL`
   - **VPC**: Select `dcmusic-dev-vpc`
3. **Add subnets**:
   - **Availability Zones**: Select `ap-south-1a` and `ap-south-1b`
   - **Subnets**: Select the 2 **private subnets** (`10.0.10.0/24` and `10.0.11.0/24`)
4. Click **Create**.

---

### 5.2 Create the MySQL Database
1. In RDS Console, click **Databases** → Click **Create database**.
2. **Choose a database creation method**: **Standard create**
3. **Engine options**:
   - Engine: **MySQL**
   - Engine Version: **MySQL 8.0.x** (latest 8.0)
4. **Templates**: Select **Free tier**
5. **Settings**:
   - **DB instance identifier**: `dcmusic-dev-mysql`
   - **Master username**: `admin`
   - **Master password**: Enter your secure password (e.g. `YourSecurePassword123!`)
   - **Confirm master password**: Re-enter password
6. **Instance configuration**:
   - **DB instance class**: `db.t3.micro`
7. **Storage**:
   - **Allocated storage**: `20` GiB
   - **Storage type**: General Purpose SSD (`gp2` or `gp3`)
   - Disable **Enable storage autoscaling**
8. **Connectivity**:
   - **Virtual private cloud (VPC)**: Select `dcmusic-dev-vpc`
   - **DB Subnet group**: Select `dcmusic-dev-db-subnet`
   - **Public access**: **No**
   - **VPC security group (firewall)**: Select **Choose existing**
     - Select: `dcmusic-dev-rds-sg`
     - Remove `default` security group if selected
9. **Additional configuration**:
   - **Initial database name**: `dcmusic_db`
   - **Backup retention period**: `7 days`
   - **Encryption**: Enable encryption
   - **Deletion protection**: Uncheck (for dev ease)
10. Click **Create database**.  
*(Creation takes ~5-8 minutes. When complete, copy the **Endpoint** address from the Connectivity & security tab).*

---

## Step 6: EKS Cluster Creation

1. Go to **EKS Console** (`https://console.aws.amazon.com/eks/`).
2. Click **Add cluster** → **Create**.
3. **Step 1: Configure cluster**:
   - **Name**: `dcmusic-eks` ⚠️ *(Exact name required)*
   - **Kubernetes version**: `1.29` (or `1.30`)
   - **Cluster service role**: Select `dcmusic-dev-eks-cluster-role`
   - Click **Next**.
4. **Step 2: Specify networking**:
   - **VPC**: Select `dcmusic-dev-vpc`
   - **Subnets**: Ensure all 4 subnets are included (2 public, 2 private)
   - **Security groups**: Select `dcmusic-dev-eks-cluster-sg`
   - **Cluster endpoint access**: Select **Public and private**
     - *(Allows kubectl from your laptop/Jenkins while internal pods use private DNS)*
   - Click **Next**.
5. **Step 3: Configure logging**:
   - Select: `API server`, `Audit`, `Authenticator`
   - Click **Next**.
6. **Step 4: Select add-ons**:
   - Ensure `vended` default add-ons are checked (`CoreDNS`, `kube-proxy`, `Amazon VPC CNI`).
   - Click **Next** → Click **Next** → Click **Create**.

*(EKS cluster provisioning takes ~10-15 minutes. Status will change from `Creating` to `Active`).*

---

## Step 7: EKS Managed Node Group

Once the cluster is **Active**:
1. Open cluster `dcmusic-eks` → Click **Compute** tab.
2. In **Node groups** section, click **Add node group**.
3. **Step 1: Configure node group**:
   - **Name**: `dcmusic-eks-general`
   - **Node IAM Role**: Select `dcmusic-dev-eks-nodes-role`
   - Click **Next**.
4. **Step 2: Set compute and scaling configuration**:
   - **AMI type**: `Amazon Linux 2 (AL2_x86_64)`
   - **Capacity type**: `On-Demand`
   - **Instance types**: Select `t3.small` (Remove any default like `t3.medium` if you want lowest cost)
   - **Disk size**: `20` GiB
   - **Node group scaling configuration**:
     - Minimum size: `1`
     - Maximum size: `3`
     - Desired size: `2`
   - Click **Next**.
5. **Step 3: Specify networking**:
   - **Subnets**: Select **ONLY the 2 private subnets** (`dcmusic-dev-private-1` and `dcmusic-dev-private-2`).
     - *Why: Worker nodes should stay private; ingress ALB routes traffic into them.*
   - **Configure SSH access**: Optional (leave Off).
   - Click **Next** → Review and click **Create**.

*(Node creation takes ~4-6 minutes. Status will turn to `Active`).*

---

## Step 8: EKS Add-ons & Local Kubeconfig Connection

Now verify the cluster connection from your terminal (or Jenkins agent).

### 8.1 Connect kubectl
Run on your machine / server:
```bash
aws eks update-kubeconfig --name dcmusic-eks --region ap-south-1
```

### 8.2 Verify Nodes
```bash
kubectl get nodes
```
Expected output:
```text
NAME                                         STATUS   ROLES    AGE   VERSION
ip-10-0-10-xxx.ap-south-1.compute.internal   Ready    <none>   3m    v1.29.x
ip-10-0-11-yyy.ap-south-1.compute.internal   Ready    <none>   3m    v1.29.x
```

### 8.3 Verify Core Add-ons
```bash
kubectl get pods -n kube-system
```
You should see `aws-node-xxx`, `coredns-xxx`, and `kube-proxy-xxx` in `Running` status.

---

## Step 9: IAM OIDC Provider & ALB Controller Role

To let the AWS Load Balancer Controller create ALBs on your behalf, connect IAM and Kubernetes using OIDC (IRSA).

### 9.1 Associate IAM OIDC Provider
Run this command from your terminal:
```bash
eksctl utils associate-iam-oidc-provider --region ap-south-1 --cluster dcmusic-eks --approve
```
*(Or in AWS Console: EKS → `dcmusic-eks` → Overview → Copy **OpenID Connect provider URL**. In IAM Console → Identity Providers → Add Provider → OpenID Connect → paste URL, Audience: `sts.amazonaws.com`).*

---

### 9.2 Create the IAM Policy for AWS Load Balancer Controller
1. Download the official policy JSON:
   ```bash
   curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.2/docs/install/iam_policy.json
   ```
2. Create IAM policy:
   ```bash
   aws iam create-policy \
     --policy-name AWSLoadBalancerControllerIAMPolicy \
     --policy-document file://iam_policy.json
   ```

---

### 9.3 Create the IAM Role for ALB Controller Service Account
Get your AWS Account ID:
```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

Create the ServiceAccount and IAM role bound together:
```bash
eksctl create iamserviceaccount \
  --cluster=dcmusic-eks \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name dcmusic-dev-lb-controller-role \
  --attach-policy-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve \
  --region ap-south-1
```

---

## Step 10: Deploy AWS Load Balancer Controller

### 10.1 Install cert-manager
```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml
kubectl wait --for=condition=available deployment/cert-manager -n cert-manager --timeout=120s
```

### 10.2 Install ALB Controller via Helm
1. Get VPC ID of `dcmusic-dev-vpc`:
   ```bash
   VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=dcmusic-dev-vpc" --query "Vpcs[0].VpcId" --output text)
   echo "VPC ID: $VPC_ID"
   ```

2. Add Helm repo and install:
   ```bash
   helm repo add eks https://aws.github.io/eks-charts
   helm repo update

   helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
     -n kube-system \
     --set clusterName=dcmusic-eks \
     --set serviceAccount.create=false \
     --set serviceAccount.name=aws-load-balancer-controller \
     --set region=ap-south-1 \
     --set vpcId=$VPC_ID
   ```

3. Verify running:
   ```bash
   kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
   # Output should show 2/2 pods Running
   ```

---

## Step 11: Connect Jenkins & App Pipeline

Now that infrastructure is manually live, update the application configurations:

### 11.1 Update `helm/dcmusic/values.yaml`
Replace placeholders with your real values:
1. `ACCOUNT_ID` → Replace with your 12-digit AWS Account ID (e.g. `369460428405`)
2. `REPLACE_RDS_ENDPOINT` → Replace with your RDS MySQL endpoint from Step 5.2.
3. `REPLACE_PASSWORD` → Replace with your DB password from Step 5.2.

Quick script to update both:
```bash
cd /home/dc/Desktop/Prod_DevOps

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier dcmusic-dev-mysql --query "DBInstances[0].Endpoint.Address" --output text)

sed -i "s/ACCOUNT_ID/${AWS_ACCOUNT_ID}/g" helm/dcmusic/values.yaml
sed -i "s/REPLACE_RDS_ENDPOINT/${RDS_ENDPOINT}/g" helm/dcmusic/values.yaml

git add helm/dcmusic/values.yaml
git commit -m "chore: set manual infrastructure endpoints in helm values"
```

### 11.2 Run Application Pipeline (`Jenkinsfile`)
In Jenkins:
1. Open job **`dcmusic-app`**.
2. Click **Build Now**.
3. All 10 stages will run:
   - Compile Java + React
   - Build & scan Docker images
   - Push to `dcmusic-backend` and `dcmusic-frontend` ECR
   - Deploy Helm chart to `dcmusic-eks`
   - Create ALB Ingress

### 11.3 Access the App
Run:
```bash
kubectl get ingress -n dcmusic
```
Copy the **ADDRESS** column:
```
http://k8s-dcmusic-xxxx.ap-south-1.elb.amazonaws.com
```
Paste in your browser to access DC Music!

---

## Resource Summary & Checklist

| # | Resource Name | AWS Service | Purpose | Verified |
|---|---|---|---|---|
| 1 | `dcmusic-dev-eks-cluster-role` | IAM | EKS Control Plane permissions | [ ] |
| 2 | `dcmusic-dev-eks-nodes-role` | IAM | EKS Worker Nodes permissions | [ ] |
| 3 | `dcmusic-dev-vpc` (`10.0.0.0/16`) | VPC | Isolated network | [ ] |
| 4 | `dcmusic-dev-public-1` / `2` | VPC Subnets | Internet-facing ALB subnets | [ ] |
| 5 | `dcmusic-dev-private-1` / `2` | VPC Subnets | EKS nodes & RDS database | [ ] |
| 6 | `dcmusic-dev-igw` & `dcmusic-dev-nat` | VPC Gateway | Internet inbound & outbound | [ ] |
| 7 | `dcmusic-dev-eks-cluster-sg` | EC2 Security | Cluster API protection | [ ] |
| 8 | `dcmusic-dev-eks-nodes-sg` | EC2 Security | Pod & Node communication | [ ] |
| 9 | `dcmusic-dev-rds-sg` | EC2 Security | Port 3306 MySQL access | [ ] |
| 10 | `dcmusic-backend` & `dcmusic-frontend` | ECR | Container image registry | [ ] |
| 11 | `dcmusic-dev-mysql` | RDS | Managed MySQL database | [ ] |
| 12 | `dcmusic-eks` | EKS | Kubernetes Cluster | [ ] |
| 13 | `dcmusic-eks-general` | EKS Node Group | 2 × `t3.small` worker nodes | [ ] |
| 14 | `aws-load-balancer-controller` | Helm / EKS | Provisions AWS ALBs for Ingress | [ ] |

---
*Created for manual AWS Portal setup — DC Music EKS Deployment.*
