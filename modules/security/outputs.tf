output "alb_sg_id" {
  value = aws_security_group.alb.id
}

output "eks_app_sg_id" {
  value = aws_security_group.eks_app.id
}

output "rds_sg_id" {
  value = aws_security_group.rds.id
}
