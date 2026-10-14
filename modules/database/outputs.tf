output "db_endpoint" {
  value = aws_db_instance.mysql.endpoint
}

output "db_address" {
  description = "Host sin puerto (DB_HOST de los pods)"
  value       = aws_db_instance.mysql.address
}

output "db_identifier" {
  value = aws_db_instance.mysql.identifier
}

output "db_name" {
  value = aws_db_instance.mysql.db_name
}

output "db_username" {
  value = aws_db_instance.mysql.username
}
