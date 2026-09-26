output "name" {
  value = google_container_cluster.cluster.name
}

output "location" {
  description = "A zone for a zonal cluster, the region for a regional one."
  value       = google_container_cluster.cluster.location
}

output "endpoint" {
  value     = google_container_cluster.cluster.endpoint
  sensitive = true
}

output "workload_pool" {
  description = "For binding Kubernetes service accounts to Google ones, with no key."
  value       = google_container_cluster.cluster.workload_identity_config[0].workload_pool
}

output "connect_command" {
  description = "How a human reaches it, so nobody has to reconstruct the flags."
  value = join(" ", [
    "gcloud container clusters get-credentials",
    google_container_cluster.cluster.name,
    "--location", google_container_cluster.cluster.location,
    "--project", var.project_id,
  ])
}

output "sandbox_pools" {
  description = "Pools running gVisor. Empty here would mean Spike A has nothing to test."
  value       = [for k, v in var.pools : k if v.sandbox]
}
