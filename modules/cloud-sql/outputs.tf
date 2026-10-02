output "instance_name" {
  value = google_sql_database_instance.main.name
}

output "private_ip_address" {
  description = "For the one-time GRANT step (see main.tf's header) and nothing else — services get a full DSN from Secret Manager, not this address alone."
  value       = google_sql_database_instance.main.private_ip_address
  sensitive   = true
}

output "admin_password_secret" {
  description = "Secret Manager secret id holding the postgres admin password, for the one-time GRANT step."
  value       = google_secret_manager_secret.admin_password.secret_id
}

output "owner_dsn_secrets" {
  description = "Secret Manager secret id per database's <name>_owner DSN, keyed the same as var.databases."
  value       = { for k, v in google_secret_manager_secret.owner_dsn : k => v.secret_id }
}

output "app_dsn_secrets" {
  description = "Secret Manager secret id per database's <name>_app DSN, keyed the same as var.databases."
  value       = { for k, v in google_secret_manager_secret.app_dsn : k => v.secret_id }
}
