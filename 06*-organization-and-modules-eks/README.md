# EKS Web App — Architecture & Setup Guide

This directory contains a production-style Terraform setup that provisions two independent web application stacks on AWS EKS. It evolved from the EC2-based setup in `06-organization-and-modules/`.

---

## Table of Contents

1. [What Was the EC2 Setup](#1-what-was-the-ec2-setup)
2. [Why Move to EKS](#2-why-move-to-eks)
3. [What Changed — EC2 vs EKS Side by Side](#3-what-changed--ec2-vs-eks-side-by-side)
4. [Current EKS Architecture](#4-current-eks-architecture)
5. [Directory Structure](#5-directory-structure)
6. [How to Deploy](#6-how-to-deploy)
7. [How to Deploy Your App After Cluster Is Up](#7-how-to-deploy-your-app-after-cluster-is-up)
8. [Current Load Balancing Setup and Its Limitation](#8-current-load-balancing-setup-and-its-limitation)
9. [Next Step — AWS Load Balancer Controller](#9-next-step--aws-load-balancer-controller)
10. [Tear Down](#10-tear-down)

---

## 1. What Was the EC2 Setup

In `06-organization-and-modules/`, the architecture was:

```
Internet
    │
    ▼
Application Load Balancer (ALB)
    │  port 80 → listener rule → forward to target group
    ▼
Target Group
    │  registered: instance_1 (port 8080), instance_2 (port 8080)
    ├── EC2 instance_1  →  runs "Hello World" Python server on port 8080
    └── EC2 instance_2  →  runs "Hello World" Python server on port 8080
    │
    ▼
RDS PostgreSQL (in its own security group, only EC2 can reach it on port 5432)
S3 Bucket       (app data storage)
```

**What Terraform managed:**
- 2 individual EC2 instances (hardcoded — `instance_1`, `instance_2`)
- ALB + listener + listener rules + target group
- Manual target group attachments (`aws_lb_target_group_attachment`)
- Security groups for EC2, ALB, RDS
- RDS PostgreSQL instance
- S3 bucket with versioning, encryption, public access block

**Key files:**
- `compute.tf` — two `aws_instance` resources with `user_data` shell scripts
- `networking.tf` — ALB, target group, all security groups
- `database.tf` — RDS instance
- `storage.tf` — S3 bucket

---

## 2. Why Move to EKS

| Pain Point in EC2 | How EKS Solves It |
|---|---|
| EC2 instances manually declared — no auto-healing | EKS node group replaces failed nodes automatically |
| `user_data` shell scripts to run the app — fragile | Docker containers — portable, versioned, reproducible |
| Scaling means editing Terraform (change `count`) | Kubernetes scales pods independently of infrastructure |
| `instance_1`, `instance_2` — rigid naming | Nodes are interchangeable; pods run wherever there's space |
| App code mixed with infra concern (user_data) | Clean separation — Terraform = infra, Kubernetes YAML = app |
| No rolling deployments | `kubectl rollout restart` replaces pods one by one, zero downtime |

---

## 3. What Changed — EC2 vs EKS Side by Side

### Compute

| | EC2 Setup | EKS Setup |
|---|---|---|
| Resource | `aws_instance` (x2, hardcoded) | `aws_eks_cluster` + `aws_eks_node_group` |
| File | `compute.tf` | `eks.tf` |
| How app runs | Shell script in `user_data` | Docker container in a Kubernetes pod |
| Scaling | Change `count` in Terraform, re-apply | `kubectl scale deployment` or HPA |
| Auto-healing | None | EKS replaces failed nodes; K8s restarts failed pods |

### IAM

| | EC2 Setup | EKS Setup |
|---|---|---|
| IAM needed? | No (EC2 had no IAM role) | Yes — two roles required |
| Cluster role | — | `eks.amazonaws.com` assumes it to manage AWS resources |
| Node role | — | `ec2.amazonaws.com` assumes it so nodes can join cluster, pull ECR images, get pod IPs |
| File | — | `iam.tf` (new file) |

**Three policies attached to the node role:**
- `AmazonEKSWorkerNodePolicy` — lets nodes join the cluster
- `AmazonEC2ContainerRegistryReadOnly` — lets nodes pull your Docker images from ECR
- `AmazonEKS_CNI_Policy` — lets pods get IP addresses (without this: pods stuck at `ContainerCreating`)

### Networking / Security Groups

| | EC2 Setup | EKS Setup |
|---|---|---|
| SG for app instances | `aws_security_group.instances` (port 8080) | `aws_security_group.nodes` (port 30080 NodePort) |
| SG for ALB | `aws_security_group.alb` | Same pattern, unchanged |
| SG for RDS | `aws_security_group.rds` | Same pattern, source changed to `nodes` SG |
| New SG | — | `aws_security_group.cluster` (port 443 — Kubernetes API) |
| Traffic from ALB | port 8080 on EC2 | port 30080 (NodePort) on EKS node |

### Load Balancing

| | EC2 Setup | EKS Setup |
|---|---|---|
| ALB | Yes | Yes (same) |
| Target group port | 8080 | 30080 (NodePort) |
| Node registration | `aws_lb_target_group_attachment` with `instance_1.id`, `instance_2.id` | `data "aws_instances"` finds nodes by EKS tag, registers all dynamically via `count` |

---

## 4. Current EKS Architecture

```
Internet
    │
    ▼
Application Load Balancer  (internet-facing, port 80)
    │  security group: alb-sg (allows 0.0.0.0/0 on port 80 inbound)
    │
    ▼
Target Group  (port 30080)
    │  health check: GET / → expects 200
    │  nodes registered via data.aws_instances + count
    ├── EKS Node 1 (EC2)  :30080
    └── EKS Node 2 (EC2)  :30080
             │
             │  NodePort 30080 → Kubernetes routes to pod port 8080
             ▼
        profile-service pod  (Spring Boot, port 8080)
             │
             ▼
        RDS PostgreSQL  (port 5432, only nodes SG can reach it)

S3 Bucket  (versioned, encrypted, no public access)
```

**Security group rules summary:**

```
alb-sg:
  inbound:  0.0.0.0/0 on port 80    ← anyone on internet can send requests
  outbound: all traffic allowed

nodes-sg:
  inbound:  only alb-sg on port 30080  ← only ALB can reach nodes (no direct internet access)

cluster-sg:
  inbound:  only nodes-sg on port 443  ← only nodes talk to Kubernetes API

rds-sg:
  inbound:  only nodes-sg on port 5432 ← only pods/nodes can reach database
```

### Two Stacks

`web-app/main.tf` calls the module twice:

| | web_app_1 | web_app_2 |
|---|---|---|
| Cluster | `web-app-1-production-cluster` | `web-app-2-production-cluster` |
| ALB | separate | separate |
| RDS | separate (`profile` db) | separate (`profile` db) |
| S3 | `web-app-1-data-*` | `web-app-2-data-*` |
| State key | `06*-organization-and-modules-eks/web-app/terraform.tfstate` | same file, both in one state |

---

## 5. Directory Structure

```
06*-organization-and-modules-eks/
├── web-app/
│   └── main.tf          # Root module — calls web-app-module twice, S3 backend config
│
└── web-app-module/      # Reusable module — all resources defined here
    ├── eks.tf            # EKS cluster, node group, launch template
    ├── iam.tf            # IAM roles and policy attachments for cluster and nodes
    ├── networking.tf     # VPC data sources, security groups, ALB, target group, node registration
    ├── database.tf       # RDS PostgreSQL
    ├── storage.tf        # S3 bucket with versioning, encryption, public access block
    ├── variables.tf      # All input variables (app_name, instance_type, db_pass etc.)
    └── outputs.tf        # cluster_name, cluster_endpoint, alb_dns_name, db_instance_addr
```

---

## 6. How to Deploy

### Prerequisites

- AWS CLI configured with a user that has EKS, EC2, RDS, S3, IAM permissions
- Terraform installed
- S3 bucket `devops-directive-tf-state-simr` and DynamoDB table `terraform-state-locking` already created (see `03-basics/aws-backend`)

### Commands

```bash
cd 06*-organization-and-modules-eks/web-app

terraform init

terraform plan \
  -var="db_pass_1=YourPassword1!" \
  -var="db_pass_2=YourPassword2!"

terraform apply \
  -var="db_pass_1=YourPassword1!" \
  -var="db_pass_2=YourPassword2!"
```

> **Note:** RDS passwords cannot contain `/`, `@`, `"`, or spaces.

### Outputs after apply

```
web_app_1_alb_dns     = "<alb-dns>.elb.amazonaws.com"
web_app_1_cluster_name = "web-app-1-production-cluster"
web_app_1_db_addr     = "<rds-endpoint>.rds.amazonaws.com"
web_app_2_alb_dns     = ...
web_app_2_cluster_name = ...
web_app_2_db_addr     = ...
```

---

## 7. How to Deploy Your App After Cluster Is Up

### Step 1 — Connect kubectl to the cluster

```bash
aws eks update-kubeconfig \
  --region ap-southeast-1 \
  --name web-app-1-production-cluster
```

### Step 2 — Build and push Docker image to ECR

```bash
# Authenticate Docker to ECR
aws ecr get-login-password --region ap-southeast-1 | \
  docker login --username AWS --password-stdin \
  <account-id>.dkr.ecr.ap-southeast-1.amazonaws.com

# Build for linux/amd64 (EKS nodes are x86_64, not ARM)
docker buildx build --platform linux/amd64 \
  -t <account-id>.dkr.ecr.ap-southeast-1.amazonaws.com/<repo>:latest \
  --push .
```

> **Important:** Always build with `--platform linux/amd64` on Apple Silicon (M1/M2 Mac), otherwise you get `exec format error` in pods.

### Step 3 — Apply Kubernetes manifests

```bash
kubectl apply -f kubernetes/deployment.yaml
kubectl apply -f kubernetes/service.yaml
```

**deployment.yaml** — tells Kubernetes how to run your container:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: profile-service
spec:
  replicas: 2
  selector:
    matchLabels:
      app: profile-service
  template:
    metadata:
      labels:
        app: profile-service
    spec:
      containers:
        - name: profile-service
          image: <ecr-url>:latest
          ports:
            - containerPort: 8080
          env:
            - name: SPRING_DATASOURCE_URL
              value: "jdbc:postgresql://<rds-endpoint>:5432/profile"
            - name: SPRING_DATASOURCE_PASSWORD
              value: "<db-pass>"
            - name: ENCRYPTION_KEY
              value: "<16-char-key>"
```

**service.yaml** — exposes the app on a NodePort so the ALB can reach it:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: profile-service
spec:
  type: NodePort
  selector:
    app: profile-service
  ports:
    - port: 80
      targetPort: 8080
      nodePort: 30080   # ALB sends traffic here on every node
```

### Step 4 — Verify

```bash
kubectl get pods               # should show Running
kubectl logs <pod-name>        # check app logs
curl http://<alb-dns-name>/    # hit the ALB
```

---

## 8. Current Load Balancing Setup and Its Limitation

### How it works today

```
Internet → ALB (port 80) → Target Group (port 30080) → Node → Pod (port 8080)
```

Traffic reaches the cluster via a fixed NodePort (30080). Every node exposes port 30080, and Kubernetes routes from that port to whichever pod is running the app.

Nodes are registered in the target group **statically** by Terraform:

```hcl
# networking.tf
data "aws_instances" "nodes" {
  filter {
    name   = "tag:eks:cluster-name"
    values = ["${var.app_name}-${var.environment_name}-cluster"]
  }
  depends_on = [aws_eks_node_group.main]
}

resource "aws_lb_target_group_attachment" "nodes" {
  count            = length(data.aws_instances.nodes.ids)
  target_group_arn = aws_lb_target_group.nodes.arn
  target_id        = data.aws_instances.nodes.ids[count.index]
  port             = 30080
}
```

### The limitation — it does not scale to multiple services

If you add a second service (`order-service`), you need:

| What you need | Where it lives | Who has to change it |
|---|---|---|
| New NodePort (e.g. 30081) | `service.yaml` | Developer |
| New security group rule for 30081 | `networking.tf` | Infra / Terraform |
| New target group | `networking.tf` | Infra / Terraform |
| New ALB listener rule | `networking.tf` | Infra / Terraform |
| New target group attachments | `networking.tf` | Infra / Terraform |

Every new service = a Terraform change + re-apply. This does not scale.

---

## 9. Next Step — AWS Load Balancer Controller

The AWS Load Balancer Controller (LBC) is a pod that runs inside your EKS cluster. It watches for Kubernetes `Ingress` resources and **automatically manages the ALB for you**. Adding a new service requires no Terraform changes — only a Kubernetes YAML file.

### What you add to Terraform (once, never changes again)

**Three things:**

#### 1. IAM OIDC Provider — identity bridge between Kubernetes and AWS IAM

```hcl
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da2b0ab7280"]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}
```

This tells AWS: "Trust identity tokens issued by this EKS cluster." Without this, pods cannot assume IAM roles.

#### 2. IAM Role for the LBC pod (IRSA — IAM Roles for Service Accounts)

```hcl
resource "aws_iam_role" "lbc" {
  name = "aws-load-balancer-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${aws_iam_openid_connect_provider.eks.url}:sub" =
            "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lbc" {
  role       = aws_iam_role.lbc.name
  policy_arn = aws_iam_policy.lbc.arn  # from official iam_policy.json
}
```

This says: "The pod named `aws-load-balancer-controller` in namespace `kube-system` is allowed to create and update ALBs in AWS."

#### 3. Install LBC via Helm

```hcl
provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.main.name]
      command     = "aws"
    }
  }
}

resource "helm_release" "aws_lbc" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.14.0"

  set {
    name  = "clusterName"
    value = aws_eks_cluster.main.name
  }
  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  depends_on = [aws_eks_node_group.main]
}
```

Helm is a package manager for Kubernetes — this is equivalent to running `helm install aws-load-balancer-controller ...` from the terminal, but managed by Terraform.

### What developers add per service (no Terraform needed)

```yaml
# ingress.yaml — one file per service, managed by the dev team
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: profile-service
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip   # routes to pod directly, skips NodePort
spec:
  rules:
    - http:
        paths:
          - path: /api/profiles
            pathType: Prefix
            backend:
              service:
                name: profile-service
                port:
                  number: 8080
```

LBC sees this file → automatically updates the ALB listener rules → traffic flows to the right pods.

### Before vs After

```
BEFORE (current — NodePort):
  Terraform manages: ALB + target group + node registration + security group rules
  Adding a service:  change Terraform, re-apply, register nodes

AFTER (with LBC):
  Terraform manages: OIDC provider + IAM role + Helm release  (done once, never touched again)
  Adding a service:  developer adds ingress.yaml → LBC handles ALB automatically
```

### Reference
- [AWS Docs — Install AWS Load Balancer Controller with Helm](https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html)
- [Full Installation Guide](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/installation/)

---

## 10. Tear Down

Before destroying, ensure `deletion_protection = false` in `database.tf` (already set in this repo).

```bash
cd 06*-organization-and-modules-eks/web-app

terraform destroy \
  -var="db_pass_1=YourPassword1!" \
  -var="db_pass_2=YourPassword2!"
```

Type `yes` when prompted. Takes approximately 15–20 minutes — RDS deletion is the slowest step.

> **Note:** If you re-apply after destroy, `terraform init` is **not** needed again as long as the S3 backend bucket still exists.
