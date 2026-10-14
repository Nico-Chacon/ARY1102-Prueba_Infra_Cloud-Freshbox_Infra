variable "project_name" {
  type = string
}

variable "db_subnets" {
  description = "Subredes privadas Data"
  type        = list(string)
}

variable "rds_sg_id" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "db_name" {
  type    = string
  default = "freshbox"
}

variable "db_username" {
  type    = string
  default = "admin"
}

variable "engine_version" {
  type    = string
  default = "8.4"
}
