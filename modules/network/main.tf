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

  # Not what makes Cloud SQL or Memorystore privately reachable — the comment here
  # previously claimed that, and it was wrong (found implementing R0-WS1-004, not in
  # review). Those services get their private IP from the separate Private Service
  # Access range below, never from this or any other subnet; nothing in this project
  # currently places a GCE-backed, taggable resource in this subnet at all. Kept because
  # removing it is a bigger question than this story (R0-WS1-011 already exists for the
  # equivalent question about the sandbox subnet) — `private_ip_google_access` stays on
  # defensively, in case something tagged `data` ever does live here.
  private_ip_google_access = true
}

# R0-WS1-004: the actual mechanism behind Cloud SQL's and Memorystore's private IP.
# Reserved purely as an address range — nothing is "in" it the way a subnet holds
# instances — then peered to Google's own tenant network, which is where these services'
# private endpoints actually live.
resource "google_compute_global_address" "private_service_access" {
  name          = "${local.prefix}-psa"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = cidrhost(var.psa_range, 0)
  prefix_length = tonumber(split("/", var.psa_range)[1])
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "private_service_access" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_access.name]
}

resource "google_compute_subnetwork" "sandbox" {
  name          = "${local.prefix}-sandbox"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.subnets.sandbox

  # On, and this reverses what was written here before. ADR-0009.
  #
  # The old comment said a pod here could otherwise reach Secret Manager and Cloud Storage
  # without leaving the VPC. That reasons about a *pod* and sets a control on a *subnet*,
  # which is the confusion ADR-0008 exists to correct: this flag governs the node.
  #
  # Off, the node could pull no image from anywhere — no NAT, no Google, no internet — so
  # the sandbox pool could not run a container at all, and the firewall's
  # `sandbox-allow-google-apis` rule permitted a destination with no route to it.
  #
  # On, the node reaches 199.36.153.8/30 and nothing else: `restricted.googleapis.com`,
  # which is the only destination the egress firewall permits besides the control plane
  # and DNS. Not the internet, not even all of Google. The pod is still denied every
  # egress by NetworkPolicy, and GKE_METADATA stops it borrowing the node's identity.
  private_ip_google_access = true

  # Full sampling: this is where untrusted, model-authored code runs, and the traffic
  # volume is low enough that the cost is worth the record.
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 1.0
    metadata             = "INCLUDE_ALL_METADATA"
  }
}
