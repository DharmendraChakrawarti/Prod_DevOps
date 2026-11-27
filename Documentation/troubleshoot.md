# 🛠️ DC Music DevOps — Complete Troubleshooting & Issue Log

This document catalogs every technical problem, root cause, error message, and resolution encountered throughout the engineering and deployment of the **DCMusic** application across **AWS, Terraform, Kubernetes (EKS), Docker, Jenkins CI/CD, and Nginx**.

---

## 📑 Table of Contents

1. [Issue 1: Terraform Init EOF on Migration Prompt in Jenkins](#issue-1-terraform-init-eof-on-migration-prompt-in-jenkins)
2. [Issue 2: Deprecated DynamoDB Locking Warning in Terraform >= 1.10](#issue-2-deprecated-dynamodb-locking-warning-in-terraform--110)
3. [Issue 3: `terraform init -input=false` Conflict with Piped Input](#issue-3-terraform-init--inputfalse-conflict-with-piped-input)
4. [Issue 4: EKS `AccessDeniedException` on Cluster Creation](#issue-4-eks-accessdeniedexception-on-cluster-creation)
5. [Issue 5: RDS `FreeTierRestrictionError` on Backup Retention Period](#issue-5-rds-freetierrestrictionerror-on-backup-retention-period)
6. [Issue 6: RDS `InvalidParameterValue` on Master Password Characters](#issue-6-rds-invalidparametervalue-on-master-password-characters)
7. [Issue 7: Unsupported Kubernetes Version 1.29 (End-of-Life on EKS)](#issue-7-unsupported-kubernetes-version-129-end-of-life-on-eks)
8. [Issue 8: Incompatible EKS Version Upgrade (Skipping Minor Versions 1.31 -> 1.35)](#issue-8-incompatible-eks-version-upgrade-skipping-minor-versions-131---135)
9. [Issue 9: Backend Deployment Rollout Timeout in Helm](#issue-9-backend-deployment-rollout-timeout-in-helm)
10. [Issue 10: Jenkins Destroy Confirmation Null Input Bug](#issue-10-jenkins-destroy-confirmation-null-input-bug)
11. [Issue 11: VPC Deletion Stuck During `terraform destroy`](#issue-11-vpc-deletion-stuck-during-terraform-destroy)
12. [Issue 12: EKS Access Entries Authentication Mode Error](#issue-12-eks-access-entries-authentication-mode-error)
13. [Issue 13: `net::ERR_CONNECTION_TIMED_OUT` on User Registration](#issue-13-neterr_connection_timed_out-on-user-registration)
14. [Issue 14: `502 Bad Gateway` from Frontend Nginx Reverse Proxy](#issue-14-502-bad-gateway-from-frontend-nginx-reverse-proxy)
15. [Issue 15: Trivy Security Scan Flagging Base Image CVEs (Build UNSTABLE)](#issue-15-trivy-security-scan-flagging-base-image-cves-build-unstable)

---

### Issue 1: Terraform Init EOF on Migration Prompt in Jenkins

- **Symptoms / Error Message**:
  ```text
  Do you want to copy existing state to the new backend?
  Enter a value: Error: EOF
  ```
- **Root Cause**:
  Jenkins runs non-interactive shell commands. When local state existed and S3 remote backend was introduced, Terraform paused asking for interactive confirmation (`yes/no`). Because stdin was closed, it received an EOF and failed.
- **Resolution**:
  Piped affirmative input into `terraform init` in `Jenkinsfile.infra`:
  ```bash
  echo "yes" | terraform init -backend-config="..."
  ```

---

### Issue 2: Deprecated DynamoDB Locking Warning in Terraform >= 1.10

- **Symptoms / Error Message**:
  ```text
  Warning: Argument "dynamodb_table" is deprecated.
  Use native S3 state locking instead.
  ```
- **Root Cause**:
  Starting with Terraform v1.10+, S3 supports native object locking using `.tflock` files, rendering separate AWS DynamoDB tables obsolete.
- **Resolution**:
  Removed DynamoDB creation from `setup-remote-state.sh` and updated `backend "s3"` configuration to use `use_lockfile = true`:
  ```hcl
  backend "s3" {
    # dynamic parameters passed in init
  }
  ```
  ```bash
  terraform init -backend-config="use_lockfile=true"
  ```

---

### Issue 3: `terraform init -input=false` Conflict with Piped Input

- **Symptoms / Error Message**:
  ```text
  terraform init: error reading input: input is disabled (-input=false)
  ```
- **Root Cause**:
  The flag `-input=false` actively blocks reading from `stdin`, defeating `echo "yes" | terraform init`.
- **Resolution**:
  Removed `-input=false` while keeping `echo "yes" | terraform init`.

---

### Issue 4: EKS `AccessDeniedException` on Cluster Creation

- **Symptoms / Error Message**:
  ```text
  Error: creating EKS Cluster (dcmusic-eks): AccessDeniedException:
  User: arn:aws:iam::328159054985:user/dcmusic-admin is not authorized to perform: eks:CreateCluster
  ```
- **Root Cause**:
  The IAM user `dcmusic-admin` lacked explicit IAM permissions for EKS cluster management.
- **Resolution**:
  Attached `AmazonEKSClusterPolicy`, `AmazonEKSWorkerNodePolicy`, and EKS admin permissions to the `dcmusic-admin` user in AWS IAM.

---

### Issue 5: RDS `FreeTierRestrictionError` on Backup Retention Period

- **Symptoms / Error Message**:
  ```text
  Error creating DB Instance: FreeTierRestrictionError:
  Backup retention period must be 1 for RDS MySQL Free Tier.
  ```
- **Root Cause**:
  Terraform defaulted `backup_retention_period = 7`. AWS RDS Free Tier (`db.t3.micro`) only allows a maximum retention period of 1 day.
- **Resolution**:
  Updated `terraform/modules/rds/variables.tf` and `terraform/modules/rds/main.tf` to default `backup_retention_period = 1`.

---

### Issue 6: RDS `InvalidParameterValue` on Master Password Characters

- **Symptoms / Error Message**:
  ```text
  InvalidParameterValue: The parameter MasterUserPassword is not a valid password.
  Only printable ASCII characters besides '/', '@', '"', ' ' may be used.
  ```
- **Root Cause**:
  The database password configured in Jenkins credentials contained special characters (`@`, `/`, `"`, or spaces) disallowed by AWS RDS.
- **Resolution**:
  Updated the Jenkins secret text credential `rds-password` to use alphanumeric characters with allowed symbols (e.g., `#`, `$`, `_`, `-`).

---

### Issue 7: Unsupported Kubernetes Version 1.29 (End-of-Life on EKS)

- **Symptoms / Error Message**:
  ```text
  Error: creating EKS Cluster: InvalidParameterException:
  Unsupported Kubernetes version 1.29
  ```
- **Root Cause**:
  Kubernetes 1.29 reached End-of-Life (EOL) standard support on AWS EKS.
- **Resolution**:
  Upgraded Kubernetes version in `terraform/variables.tf` to `1.35` (supported through March 2027) with Amazon Linux 2023 nodes (`AL2023_x86_64_STANDARD`).

---

### Issue 8: Incompatible EKS Version Upgrade (Skipping Minor Versions 1.31 -> 1.35)

- **Symptoms / Error Message**:
  ```text
  Error: updating EKS Cluster (dcmusic-eks) version: InvalidParameterException:
  Unsupported Kubernetes version update from 1.31 to 1.35
  ```
- **Root Cause**:
  Kubernetes requires sequential minor version upgrades (1.31 -> 1.32 -> 1.33 -> 1.34 -> 1.35) and prevents jumping across multiple versions.
- **Resolution**:
  Ran `Jenkinsfile.infra.delete` to clean up the existing 1.31 cluster, and provisioned a fresh cluster directly on version `1.35`.

---

### Issue 9: Backend Deployment Rollout Timeout in Helm

- **Symptoms / Error Message**:
  ```text
  Error: UPGRADE FAILED: timed out waiting for the condition
  deployment "dcmusic-backend" exceeded its progress deadline
  ```
- **Root Cause**:
  Three contributing factors:
  1. Spring Security blocked Actuator health probe endpoints (`/actuator/**`) with HTTP 401 Unauthorized, causing Kubernetes liveness/readiness probes to kill the containers.
  2. The RDS endpoint was using placeholder text (`REPLACE_RDS_ENDPOINT`).
  3. The RDS Security Group did not allow inbound traffic from the EKS VPC CIDR.
- **Resolution**:
  1. Updated `backend/src/main/java/com/dcmusic/config/SecurityConfig.java`:
     ```java
     .requestMatchers("/actuator/**").permitAll()
     ```
  2. Updated `Jenkinsfile` deploy stage to fetch the live RDS endpoint via AWS CLI:
     ```bash
     rdsHost=$(aws rds describe-db-instances --query 'DBInstances[0].Endpoint.Address' --output text)
     ```
     and pass `--set backend.secret.SPRING_DATASOURCE_URL="jdbc:mysql://${rdsHost}:3306/dcmusic_db"`.
  3. Added `cidr_blocks = [var.vpc_cidr]` to the RDS Security Group in `terraform/modules/security/main.tf`.

---

### Issue 10: Jenkins Destroy Confirmation Null Input Bug

- **Symptoms / Error Message**:
  ```text
  Cluster name mismatch! You typed 'null' but expected 'dcmusic-eks'. Aborting.
  ```
- **Root Cause**:
  In Jenkins Pipeline syntax, the `input` step returns the value entered by the user, but the script checked `env.CONFIRM_CLUSTER_NAME` which was never placed into the pipeline environment automatically.
- **Resolution**:
  Updated `Jenkinsfile.infra.delete` to capture the return value from `input(...)`:
  ```groovy
  def userInput = input(...)
  def confirmName = (userInput instanceof Map) ? userInput['CONFIRM_CLUSTER_NAME'] : userInput?.toString()
  if (confirmName?.trim() != env.EKS_CLUSTER_NAME) {
      error "Cluster name mismatch! ..."
  }
  ```

---

### Issue 11: VPC Deletion Stuck During `terraform destroy`

- **Symptoms / Error Message**:
  ```text
  module.vpc.aws_subnet.public[0]: Still destroying... [02m30s elapsed]
  module.vpc.aws_internet_gateway.main: Still destroying... [02m30s elapsed]
  module.vpc.aws_vpc.main: Still destroying... [01m40s elapsed]
  ```
- **Root Cause**:
  AWS cannot delete a VPC, subnet, or Internet Gateway if active Network Interfaces (ENIs) exist. A manually created EC2 jumper/bastion instance had an attached ENI in the public subnet.
- **Resolution**:
  Terminated the manual EC2 jumper instance in the AWS Console, releasing its network interface and allowing VPC teardown to complete cleanly.

---

### Issue 12: EKS Access Entries Authentication Mode Error

- **Symptoms / Error Message**:
  ```text
  Error loading access entries:
  The cluster's authentication mode must be set to one of [API, API_AND_CONFIG_MAP] to perform this operation.
  ```
- **Root Cause**:
  EKS clusters created prior to API authentication defaults only supported the legacy `aws-auth` ConfigMap mode.
- **Resolution**:
  Added the `access_config` block into `terraform/modules/eks/main.tf`:
  ```hcl
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
  ```

---

### Issue 13: `net::ERR_CONNECTION_TIMED_OUT` on User Registration

- **Symptoms / Error Message**:
  ```text
  Failed to load resource: net::ERR_CONNECTION_TIMED_OUT
  (POST http://<frontend-loadbalancer>:8080/api/auth/register)
  ```
- **Root Cause**:
  In `frontend/src/api.js`, the code called `http://${window.location.hostname}:8080/api`. On AWS, the Frontend LoadBalancer only listens on port **80**. Port 8080 does not exist on that ELB, causing AWS security firewalls to drop all packets silently until browser timeout.
- **Resolution**:
  1. Configured Nginx in `frontend/Dockerfile` to reverse proxy `/api/` requests internally to the backend service.
  2. Changed `frontend/src/api.js` to make relative requests to `/api`.

---

### Issue 14: `502 Bad Gateway` from Frontend Nginx Reverse Proxy

- **Symptoms / Error Message**:
  ```html
  <html> <head><title>502 Bad Gateway</title></head>
  <body><center><h1>502 Bad Gateway</h1></center><hr><center>nginx/1.31.10</center></body>
  </html>
  ```
- **Root Cause**:
  Two issues:
  1. Nginx used a dynamic variable in `proxy_pass http://$backend_upstream;` with a hardcoded DNS resolver (`172.20.0.10`). In AWS EKS, CoreDNS uses dynamically allocated ClusterIPs (`10.100.0.10`), causing Nginx DNS lookups to fail.
  2. The backend was addressed with a short name (`dcmusic-backend`) without the Kubernetes cluster domain suffix.
- **Resolution**:
  1. Replaced the dynamic variable proxy with a standard Nginx `upstream` block in `frontend/Dockerfile`:
     ```nginx
     upstream backend_service {
         server ${BACKEND_HOST}:${BACKEND_PORT} max_fails=3 fail_timeout=10s;
         keepalive 32;
     }

     location /api/ {
         proxy_pass http://backend_service;
         proxy_http_version 1.1;
         proxy_set_header Host $host;
         proxy_set_header X-Real-IP $remote_addr;
         proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
     }
     ```
  2. Passed the cluster Fully Qualified Domain Name (FQDN) in `helm/dcmusic/templates/frontend-configmap.yaml`:
     ```yaml
     BACKEND_HOST: dcmusic-backend.dcmusic.svc.cluster.local
     BACKEND_PORT: "8080"
     ```

---

### Issue 15: Trivy Security Scan Flagging Base Image CVEs (Build UNSTABLE)

- **Symptoms / Error Message**:
  ```text
  Total: 4 (CRITICAL: 4)
  WARNING: Backend image has CRITICAL vulnerabilities!
  Build result set to UNSTABLE
  ```
- **Root Cause**:
  Upstream Maven and Eclipse-Temurin base images had newly discovered CVEs.
- **Resolution**:
  Used soft-fail handling (`unstable(...)` instead of `error(...)`) in `Jenkinsfile` Stage 6. This flags security concerns in the Jenkins dashboard without completely halting production delivery during base image patch cycles.
