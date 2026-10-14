output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "vpc_id" {
  value = module.networking.vpc_id
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "node_group_asg_name" {
  value = module.eks.node_group_asg_name
}

output "alb_sg_id" {
  description = "SG del ALB (lo usa el Ingress)"
  value       = module.security.alb_sg_id
}

output "db_address" {
  description = "Host de RDS (DB_HOST)"
  value       = module.database.db_address
}

output "db_endpoint" {
  value = module.database.db_endpoint
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "sns_topic_arn" {
  value = module.monitoring.sns_topic_arn
}
