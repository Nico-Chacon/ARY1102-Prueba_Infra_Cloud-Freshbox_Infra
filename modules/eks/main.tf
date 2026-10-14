# EKS + Node Group administrado. En AWS Academy no se pueden crear roles IAM,
# por eso el cluster y los nodos usan el rol existente "LabRole".
data "aws_iam_role" "lab" {
  name = var.lab_role_name
}

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = data.aws_iam_role.lab.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = concat(var.private_app_subnet_ids, var.public_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  upgrade_policy {
    support_type = "STANDARD"
  }

  tags = { Name = var.cluster_name }
}

# Launch Template: SG propio (capa App), EBS cifrado, IMDSv2 con hop limit 2
# (los pods del ALB Controller / Cluster Autoscaler / CloudWatch usan el rol del nodo)
resource "aws_launch_template" "nodes" {
  name_prefix = "${var.cluster_name}-ng-"

  vpc_security_group_ids = [
    var.eks_app_sg_id,
    aws_eks_cluster.main.vpc_config[0].cluster_security_group_id,
  ]

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true # EBS Encryption
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.common_tags, { Name = "${var.cluster_name}-node" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(var.common_tags, { Name = "${var.cluster_name}-node-vol" })
  }
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-ng"
  node_role_arn   = data.aws_iam_role.lab.arn
  subnet_ids      = var.private_app_subnet_ids
  instance_types  = [var.node_instance_type]
  ami_type        = "AL2023_ARM_64_STANDARD"
  capacity_type   = "ON_DEMAND"

  scaling_config {
    min_size     = var.node_min
    desired_size = var.node_desired
    max_size     = var.node_max
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  labels = { role = "app" }

  # El Cluster Autoscaler cambia desired_size; Terraform no debe revertirlo
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  tags = { Name = "${var.cluster_name}-ng" }
}

# Metrics Server (requisito del HPA)
resource "aws_eks_addon" "metrics_server" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "metrics-server"
  resolve_conflicts_on_create = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.main]
}

# CloudWatch Container Insights (add-on oficial; usa el rol del nodo = LabRole)
resource "aws_eks_addon" "container_insights" {
  count                       = var.enable_container_insights ? 1 : 0
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "amazon-cloudwatch-observability"
  resolve_conflicts_on_create = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.main]

  timeouts {
    create = "15m"
  }
}
