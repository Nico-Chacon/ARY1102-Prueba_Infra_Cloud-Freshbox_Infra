output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "cluster_security_group_id" {
  value = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "node_group_name" {
  value = aws_eks_node_group.main.node_group_name
}

output "node_group_asg_name" {
  description = "ASG del Node Group (lo usa el Cluster Autoscaler)"
  value       = aws_eks_node_group.main.resources[0].autoscaling_groups[0].name
}
