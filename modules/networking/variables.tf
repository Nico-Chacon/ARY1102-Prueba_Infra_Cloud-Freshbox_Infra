variable "project_name" {
  description = "Prefijo de nombres"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR de la VPC (/22)"
  type        = string
  default     = "10.0.0.0/22"
}

variable "cluster_name" {
  description = "Nombre del cluster EKS (tags de descubrimiento de subredes para el ALB Controller)"
  type        = string
}
