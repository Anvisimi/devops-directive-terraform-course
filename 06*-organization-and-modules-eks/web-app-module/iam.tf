# ─────────────────────────────────────────────
# CLUSTER ROLE — gives the EKS control plane
# permission to manage AWS resources on your behalf
# (create ENIs, manage load balancers etc.)
# ─────────────────────────────────────────────

resource "aws_iam_role" "cluster" {
  name = "${var.app_name}-${var.environment_name}-eks-cluster-role"

  # "assume_role_policy" = who is ALLOWED to use this role
  # Here: only the EKS service itself can assume it
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Attach AWS managed policy — gives the cluster role all permissions it needs
resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ─────────────────────────────────────────────
# NODE ROLE — gives EC2 nodes (the machines
# your pods run on) permission to:
#   1. join the cluster
#   2. pull Docker images from ECR
#   3. set up pod networking
# ─────────────────────────────────────────────

resource "aws_iam_role" "node" {
  name = "${var.app_name}-${var.environment_name}-eks-node-role"

  # Only EC2 service can assume this role (not EKS, not Lambda)
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Policy 1: lets nodes join and communicate with EKS control plane
resource "aws_iam_role_policy_attachment" "node_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# Policy 2: lets nodes pull YOUR Docker images from ECR
# (this is why your existing GitHub Actions push works — nodes can pull it)
resource "aws_iam_role_policy_attachment" "node_ecr_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Policy 3: lets pods get IP addresses (CNI = Container Network Interface)
# without this: pods stuck at "ContainerCreating", no network
resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}