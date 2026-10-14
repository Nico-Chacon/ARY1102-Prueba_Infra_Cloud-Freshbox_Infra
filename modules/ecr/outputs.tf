output "repository_urls" {
  description = "Mapa nombre -> URL del repositorio"
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}
