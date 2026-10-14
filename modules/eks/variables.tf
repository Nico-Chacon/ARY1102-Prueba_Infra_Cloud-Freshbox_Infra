variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  type    = string
  default = "1.35"
}

variable "lab_role_name" {
  type    = string
  default = "LabRole"
}

variable "private_app_subnet_ids" {
  type = list(string)
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "eks_app_sg_id" {
  type = string
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

variable "common_tags" {
  type    = map(string)
  default = {}
}
