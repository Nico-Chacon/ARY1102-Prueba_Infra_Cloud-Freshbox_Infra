variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  description = "Prefijo de nombres de recursos"
  type        = string
  default     = "freshbox"
}

variable "student_tag" {
  description = "Se agrega a los valores de los tags (Project, CostCenter, Student)"
  type        = string
  default     = "chacon"
}

variable "owner_name" {
  description = "Valor del tag Owner (viene del secret OWNER_NAME). Evita el caracter &"
  type        = string
  default     = "chacon"
}

variable "cluster_name" {
  type    = string
  default = "freshbox-cluster"
}

variable "kubernetes_version" {
  type    = string
  default = "1.35"
}

variable "vpc_cidr" {
  description = "VPC /22 del enunciado"
  type        = string
  default     = "10.0.0.0/22"
}

variable "db_password" {
  description = "Password RDS (secret DB_PASSWORD via TF_VAR_db_password)"
  type        = string
  sensitive   = true
}

variable "db_name" {
  type    = string
  default = "freshbox"
}

variable "db_username" {
  type    = string
  default = "admin"
}

variable "db_engine_version" {
  type    = string
  default = "8.4"
}

variable "email_sns" {
  description = "Correo para alertas SNS (secret EMAIL_SNS)"
  type        = string
}

variable "node_instance_type" {
  type    = string
  default = "t4g.small"
}

variable "node_min" {
  type    = number
  default = 2
}

variable "node_desired" {
  type    = number
  default = 3
}

variable "node_max" {
  type    = number
  default = 4
}

variable "enable_container_insights" {
  type    = bool
  default = true
}
