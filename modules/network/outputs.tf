output "network_id" {
  value = google_compute_network.vpc.id
}

output "network_name" {
  value = google_compute_network.vpc.name
}

output "subnets" {
  description = "Subnet self-links by zone, for the cluster and data modules."
  value = {
    edge     = google_compute_subnetwork.edge.id
    services = google_compute_subnetwork.services.id
    data     = google_compute_subnetwork.data.id
    sandbox  = google_compute_subnetwork.sandbox.id
  }
}

output "secondary_ranges" {
  description = "GKE pod and service range names, for R0-WS1-002."
  value = {
    pods     = "${local.prefix}-pods"
    services = "${local.prefix}-services"
  }
}

output "nat_address" {
  description = "The one address this platform's egress comes from. Give it to providers that allow-list."
  value       = google_compute_address.nat.address
}

output "sandbox_has_egress" {
  description = <<-EOT
    False until an egress proxy address is configured. While false a sandbox has no
    permitted egress at all, which is the correct state before sandbox-controller exists.
  EOT
  value       = var.egress_proxy_ip != ""
}
