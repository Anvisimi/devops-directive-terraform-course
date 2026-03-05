data "aws_vpc" "default_vpc" {
  default = true
}

data "aws_subnets" "default_subnet" {
  filter {
      name   = "vpc-id"
      values = [data.aws_vpc.default_vpc.id]
    }
}

# ── NEW SG: cluster control plane ─────────────────────────────────
# Same pattern as your aws_security_group "instances" and "alb"
# This controls who can talk to the Kubernetes API (port 443)

resource "aws_security_group" "cluster" {
  name   = "${var.app_name}-${var.environment_name}-cluster-sg"
  vpc_id = data.aws_vpc.default_vpc.id
}

resource "aws_security_group_rule" "cluster_inbound" {
  type                     = "ingress"
  security_group_id        = aws_security_group.cluster.id
  from_port                = 443          # Kubernetes API port
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.nodes.id  # only nodes talk to control plane
}

# ── RENAMED SG: "instances" becomes "nodes" ───────────────────────
# Exact same concept — your EC2 instances wore aws_security_group.instances
# Your EKS nodes wear aws_security_group.nodes

resource "aws_security_group" "nodes" {
  name = "${var.app_name}-${var.environment_name}-nodes-sg"
  vpc_id = data.aws_vpc.default_vpc.id
}

#what traffic EC2 accepts
resource "aws_security_group_rule" "nodes_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.nodes.id

  from_port   = 30080
  to_port     = 30080
  protocol    = "tcp"
  source_security_group_id = aws_security_group.alb.id  # only ALB can reach nodes
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.load_balancer.arn
  port = 80
  protocol = "HTTP"

  # By default, return a simple 404 page
  default_action {
    target_group_arn = aws_lb_target_group.nodes.arn
    type = "forward"
  }
}

resource "aws_lb_target_group" "nodes" {
  name     = "${var.app_name}-${var.environment_name}-nodes-tg"
  port     = 30080
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default_vpc.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}


resource "aws_security_group" "alb" {
  name = "${var.app_name}-${var.environment_name}-alb-sg"
  vpc_id=data.aws_vpc.default_vpc.id
}

resource "aws_security_group_rule" "alb_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.alb.id

  from_port   = 80
  to_port     = 80
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"] # ALB is supposed to accept traffic from internet on port 80

}

#traffic going out from ALB
resource "aws_security_group_rule" "alb_outbound" {
  type              = "egress"
  security_group_id = aws_security_group.alb.id

  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]

}


resource "aws_lb" "load_balancer" {
  name               = "${var.app_name}-${var.environment_name}-web-app-lb"
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default_subnet.ids
  security_groups    = [aws_security_group.alb.id]
  internal           = false

}

resource "aws_security_group" "rds" {
  name   = "${var.app_name}-${var.environment_name}-rds-sg"
  vpc_id = data.aws_vpc.default_vpc.id
}

resource "aws_security_group_rule" "rds_inbound" {
  type                     = "ingress"
  security_group_id        = aws_security_group.rds.id
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.nodes.id
}

data "aws_instances" "nodes" {
  filter {
    name   = "tag:eks:cluster-name"
    values = ["${var.app_name}-${var.environment_name}-cluster"]
  }

  depends_on = [aws_eks_node_group.main]  # wait for nodes to exist first
}

resource "aws_lb_target_group_attachment" "nodes" {
  count            = length(data.aws_instances.nodes.ids)
  target_group_arn = aws_lb_target_group.nodes.arn
  target_id        = data.aws_instances.nodes.ids[count.index]
  port             = 30080
}