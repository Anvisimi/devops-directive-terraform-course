# ─────────────────────────────────────────────────────────────────
# EKS EQUIVALENT:
# Instead of declaring individual EC2s, you declare a cluster
# and a node group that manages EC2s for you
# ─────────────────────────────────────────────────────────────────

resource "aws_eks_cluster" "main" {
  name     = "${var.app_name}-${var.environment_name}-cluster"
  role_arn = aws_iam_role.cluster.arn      # cluster identity (from iam.tf)
  version  = var.k8s_version               # e.g. "1.29"

  vpc_config {
    subnet_ids         = data.aws_subnets.default_subnet.ids  # same data source you know
    security_group_ids = [aws_security_group.cluster.id]      # same SG pattern
  }

  # cluster depends on the policy being attached first
  # otherwise cluster starts before it has permissions
  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.app_name}-${var.environment_name}-nodes"
  node_role_arn   = aws_iam_role.node.arn      # node identity (from iam.tf)
  subnet_ids      = data.aws_subnets.default_subnet.ids

  instance_types = [var.instance_type]     # same variable concept — "t3.micro"

  scaling_config {
    desired_size = var.node_count           # how many nodes to create (was count = 2)
    min_size     = 1                        # scale down to 1 under low load
    max_size     = 5                        # scale up to 5 under high load
  }

  # nodes depend on ALL three policies being attached
  # same reason as cluster — permissions must exist before nodes start
  depends_on = [
    aws_iam_role_policy_attachment.node_policy,
    aws_iam_role_policy_attachment.node_ecr_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
  ]

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }
}

resource "aws_launch_template" "nodes" {
  name_prefix            = "${var.app_name}-${var.environment_name}-nodes-lt"
  vpc_security_group_ids = [aws_security_group.nodes.id,aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]  # THIS is the attachment
}