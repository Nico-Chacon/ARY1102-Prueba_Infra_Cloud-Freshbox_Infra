terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Tagging obligatorio aplicado automaticamente a TODOS los recursos
  default_tags {
    tags = local.common_tags
  }
}
