output "host" {
  description = "Private IP. Services should read the full connection URL from Secret Manager (redis_url_secret), not assemble it from this."
  value       = google_redis_instance.main.host
  sensitive   = true
}

output "redis_url_secret" {
  description = "Secret Manager secret id holding the full redis:// URL, including AUTH."
  value       = google_secret_manager_secret.redis_url.secret_id
}
