terraform {
  backend "s3" {
    # Bucket creado a mano (Fase 0 de la guia). Los nombres de bucket son globales:
    # si ya existe, cambia este valor.
    bucket       = "chacon-freshbox-ep2-tfstate"
    key          = "dev/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
