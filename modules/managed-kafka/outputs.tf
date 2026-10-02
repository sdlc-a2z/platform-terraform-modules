output "cluster_id" {
  value = google_managed_kafka_cluster.main.cluster_id
}

output "bootstrap_address" {
  description = <<-EOT
    Not exposed by this resource as a plain attribute. Retrieve with:
      gcloud managed-kafka clusters describe <cluster_id> --location=<region> --format='value(bootstrapAddress)'

    That field's own hostname did NOT resolve from inside the VPC when checked live
    (R0-WS1-004) — NXDOMAIN, confirmed from both a pod's cluster DNS and a pod using the
    node's own resolver (dnsPolicy: Default), ruling out a GKE-specific DNS-forwarding
    gap. The hostname that actually works is the one Cloud DNS really registers: list
    `gcloud dns managed-zones list --filter="name~^gmk-"` for the per-cluster private
    zone, then `gcloud dns record-sets list --zone=<that zone>` for the real
    `bootstrap-<hash>....cloud.goog` A record. Unverified why the two differ — flagging
    for whoever connects a real client, not papering over it.
  EOT
  value       = google_managed_kafka_cluster.main.name
}
