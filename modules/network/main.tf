# The four network zones from HLD §10.2.
#
# This is the platform's outermost security boundary. Everything else — gVisor, the
# command policy, the tool belt — assumes a sandbox cannot reach the internet or the
# metadata server. If this module is wrong, those controls are defence in depth around a
# hole.

locals {
  prefix = "${var.environment}-aisdlc"

  # Link-local. The metadata server lives at 169.254.169.254 and hands out the node's
  # service-account token to anything that asks. Reaching it from a sandbox is a full
  # credential compromise, so it is denied explicitly rather than relied upon to be
  # unreachable.
  metadata_cidr = "169.254.169.254/32"
}

resource "google_compute_network" "vpc" {
  name    = "${local.prefix}-vpc"
  project = var.project_id

  # No default subnets: they are created in every region, which would put usable address
  # space in places nothing should be running.
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  description = "AI-SDLC platform. Four zones per HLD §10.2; isolation is enforced by the firewall rules in this module."
}

resource "google_compute_subnetwork" "edge" {
  name          = "${local.prefix}-edge"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.subnets.edge

  # Flow logs on the zones that face the internet or run untrusted code. Not everywhere:
  # they are billed per gigabyte and the data zone's traffic is already the least
  # interesting and the highest volume.
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_subnetwork" "services" {
  name                     = "${local.prefix}-services"
  project                  = var.project_id
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = var.subnets.services
  private_ip_google_access = true

  # GKE's pod and service ranges. Secondary rather than carved out of the primary, so the
  # cluster can grow without renumbering the subnet.
  secondary_ip_range {
    range_name    = "${local.prefix}-pods"
    ip_cidr_range = var.pods_cidr
  }
  secondary_ip_range {
    range_name    = "${local.prefix}-services"
    ip_cidr_range = var.services_cidr
  }
}

resource "google_compute_subnetwork" "data" {
  name          = "${local.prefix}-data"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.subnets.data

  # Private Google Access so Cloud SQL and Memorystore are reachable without a public
  # address anywhere in this zone.
  private_ip_google_access = true
}

resource "google_compute_subnetwork" "sandbox" {
  name          = "${local.prefix}-sandbox"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.subnets.sandbox

  # Explicitly false. With it on, a pod here could reach Google APIs — including Secret
  # Manager and Cloud Storage — without leaving the VPC, which is exactly the exfiltration
  # path this zone exists to close.
  private_ip_google_access = false

  # Full sampling: this is where untrusted, model-authored code runs, and the traffic
  # volume is low enough that the cost is worth the record.
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 1.0
    metadata             = "INCLUDE_ALL_METADATA"
  }
}
