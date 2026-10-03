# Egress to the internet for the services zone, and nothing else.
#
# "Named subnets, not the whole network" doesn't do the job alone (R0-WS1-011): every
# node pool, sandbox included, has its primary NIC in `services` — there is no separate
# subnet for the sandbox pool to be excluded from. `ALL_SUBNETWORKS_ALL_IP_RANGES` would
# still be worse (it would also cover any future subnet added here without a review), but
# what actually stops a sandbox node from using this NAT gateway is
# `firewall.tf`'s `target_tags = ["sandbox"]` deny-internet rule at priority 120, evaluated
# before a packet ever reaches NAT. If that firewall rule were removed, a sandbox node
# would reach the real internet through this same gateway — the subnet list below has
# never been the control.

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

  # LIST_OF_SUBNETWORKS, not ALL_SUBNETWORKS_ALL_IP_RANGES — so a future subnet added to
  # this VPC gets no NAT route by default and has to be added here deliberately. Not what
  # stops a sandbox node specifically (see this file's header comment): that's the
  # firewall tag rule, since sandbox shares this list's own `services` entry.
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
