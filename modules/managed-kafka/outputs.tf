output "cluster_id" {
  value = google_managed_kafka_cluster.main.cluster_id
}

output "bootstrap_address" {
  description = "Not yet exposed by this resource as a plain attribute — see the module README for how to retrieve it (`gcloud managed-kafka clusters describe`) until it is."
  value       = google_managed_kafka_cluster.main.name
}
