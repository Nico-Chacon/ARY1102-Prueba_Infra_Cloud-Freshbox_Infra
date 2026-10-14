# ============================================================
# FreshBox SpA - EP2 ARY1102 Arquitectura Cloud
# Orquestacion de contenedores (EKS) + PaaS (RDS Multi-AZ)
# ============================================================

locals {
  common_tags = {
    Project     = "${var.project_name}-${var.student_tag}"
    Environment = "dev"
    Owner       = var.owner_name
    CostCenter  = "ecommerce-${var.student_tag}"
    ManagedBy   = "terraform"
    Course      = "ARY1102-EP2"
    Student     = var.student_tag
  }
}

data "aws_caller_identity" "current" {}

# Capa 1/2/3: VPC /22, 6 subredes /25 en 2 AZ
module "networking" {
  source       = "../../modules/networking"
  project_name = var.project_name
  vpc_cidr     = var.vpc_cidr
  cluster_name = var.cluster_name
}

# Security Groups por capa: ALB -> EKS App -> RDS
module "security" {
  source       = "../../modules/security"
  project_name = var.project_name
  vpc_id       = module.networking.vpc_id
}

# ECR: 5 repositorios
module "ecr" {
  source       = "../../modules/ecr"
  project_name = var.project_name
}

# Capa 3: RDS MySQL Multi-AZ
module "database" {
  source         = "../../modules/database"
  project_name   = var.project_name
  db_subnets     = module.networking.private_subnets_data
  rds_sg_id      = module.security.rds_sg_id
  db_password    = var.db_password
  db_name        = var.db_name
  db_username    = var.db_username
  engine_version = var.db_engine_version
}

# Capa 2: EKS + Node Group (t4g.small, min 2 / max 4)
module "eks" {
  source                    = "../../modules/eks"
  cluster_name              = var.cluster_name
  kubernetes_version        = var.kubernetes_version
  private_app_subnet_ids    = module.networking.private_subnets_app
  public_subnet_ids         = module.networking.public_subnets
  eks_app_sg_id             = module.security.eks_app_sg_id
  node_instance_type        = var.node_instance_type
  node_min                  = var.node_min
  node_desired              = var.node_desired
  node_max                  = var.node_max
  enable_container_insights = var.enable_container_insights
  common_tags               = local.common_tags
}

# Observabilidad: SNS + alarmas RDS + dashboard
module "monitoring" {
  source        = "../../modules/monitoring"
  project_name  = var.project_name
  aws_region    = var.aws_region
  cluster_name  = var.cluster_name
  db_identifier = module.database.db_identifier
  email_sns     = var.email_sns
}
