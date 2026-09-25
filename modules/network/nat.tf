# Egress to the internet for the services zone, and nothing else.
#
# Services must reach LLM providers, GitHub and tool APIs. The sandbox must not, which is
# why NAT is attached to named subnets rather than the whole network — the default,
# ALL_SUBNETWORKS_ALL_IP_RANGES, would hand the sandbox a route to the internet and quietly
# undo the firewall rules next door.

resource "google_compute_router" "router" {
  name    = "${local.prefix}-router"
  project = var.project_id
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_address" "nat" {
  name         = "${local.prefix}-nat"
  project      = var.project_id
  region       = var.region
  address_type = "EXTERNAL"

  # A static address so egress is attributable and allow-listable: providers and customer
  # SCM instances can be told the one address this platform calls from.
  description = "Static egress address for the services zone."
}

resource "google_compute_router_nat" "nat" {
  name    = "${local.prefix}-nat"
  project = var.project_id
  region  = var.region
  router  = google_compute_router.router.name

  nat_ip_allocate_option = "MANUAL_ONLY"
  nat_ips                = [google_compute_address.nat.self_link]

  # The load-bearing line. LIST_OF_SUBNETWORKS, and the sandbox subnet is not in the list.
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.services.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  subnetwork {
    name                    = google_compute_subnetwork.edge.id
    source_ip_ranges_to_nat = ["PRIMARY_IP_RANGE"]
  }

  # Errors only. Logging every successful translation from a busy services zone is a large
  # bill for data nobody reads; a dropped translation means port exhaustion, which is worth
  # an alert.
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
