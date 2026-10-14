# RDS MySQL Multi-AZ en la capa privada Data
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = var.db_subnets
  tags       = { Name = "${var.project_name}-db-subnet-group" }
}

resource "aws_db_instance" "mysql" {
  identifier     = "${var.project_name}-db"
  engine         = "mysql"
  engine_version = var.engine_version
  instance_class = "db.t4g.small"

  allocated_storage     = 20
  max_allocated_storage = 50
  storage_type          = "gp3"
  storage_encrypted     = true # Cifrado en reposo

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_sg_id]
  publicly_accessible    = false

  multi_az = true # Alta disponibilidad: standby sincrono en otra AZ

  # Snapshots automaticos
  backup_retention_period  = 7
  backup_window            = "03:00-04:00"
  maintenance_window       = "mon:04:30-mon:05:30"
  copy_tags_to_snapshot    = true
  delete_automated_backups = true

  auto_minor_version_upgrade      = true
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]

  skip_final_snapshot = true
  deletion_protection = false

  tags = { Name = "${var.project_name}-db" }
}
