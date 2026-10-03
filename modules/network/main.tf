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
  # Access range below, never from this or any other subnet.
  #
  # This subnet does have a real tenant now, just not either of the ones first claimed:
  # Managed Kafka attaches directly to a VPC subnet (`gcp_config.access_config` — ADR-0006,
  # it sits inside the VPC rather than behind classic peering), and this is that subnet.
  # It is still not a GCE instance and still carries no `data` tag, so the tag-based
  # firewall rules below remain inert for it too — enforcement is
  # `services_allow_to_data_zone`'s source-tagged egress rule, the same shape PSA's
  # services use. `private_ip_google_access` stays on regardless, in case something
  # tagged `data` ever lives here too.
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

# R0-WS1-011: there used to be a `google_compute_subnetwork.sandbox` here, with
# `private_ip_google_access = true` and full-sampling flow logs — ADR-0009's decision,
# applied to the wrong resource. The GKE cluster takes exactly one subnetwork
# (`environments/dev/main.tf`'s `subnetwork = module.network.subnets.services`), and every
# node pool's primary NIC — sandbox included — is provisioned there, never here. Confirmed
# live: a real sandbox-pool node's NIC is in `dev-aisdlc-services`, and
# `dev-aisdlc-sandbox` carried zero instances the entire time this resource existed. The
# PGA flag and the flow logs were both inert from the moment they were written — a GCP
# API call that succeeded, attached to a resource nothing used, the same shape as
# ADR-0009's own firewall-rule finding before it.
#
# What actually makes image pulls work for the real node (confirmed live): `services`
# already had `private_ip_google_access = true` for unrelated reasons predating this
# story, and the private DNS zones for `googleapis.com`/`pkg.dev` (below) resolve
# correctly regardless of which subnet asks — those attach to the VPC, not to a subnet.
# What actually contains the node (also confirmed, and ADR-0008's point exactly):
# `firewall.tf`'s `target_tags = ["sandbox"]` rules, not subnet membership. Removing this
# resource changes none of that, because none of that ever depended on it.
#
# The full-sampling flow-log intent ("this is where untrusted, model-authored code runs")
# was real and is not replaced here — enabling it on `services` would log every other node
# pool's traffic too, a different cost/scope tradeoff than a dedicated subnet's, and is a
# separate decision this story doesn't make. Flagged, not silently dropped.
