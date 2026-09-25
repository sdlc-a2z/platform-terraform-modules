# Firewall. This file is the network zone boundary from HLD §10.2.
#
# GCP evaluates by priority, lowest number first, and stops at the first match. So the
# denies that matter sit at low numbers and the allows sit above them: a later "allow all
# egress" cannot undo an earlier deny. Getting that order wrong is silent — everything
# still works, and the control is simply absent.

# --------------------------------------------------------------------- sandbox egress
#
# The sandbox runs model-authored code. Three denies at the lowest priorities, before any
# allow in this file or any default, because each closes a path that turns "untrusted code
# ran" into "credentials left the building".

resource "google_compute_firewall" "sandbox_deny_metadata" {
  name      = "${local.prefix}-sandbox-deny-metadata"
  project   = var.project_id
  network   = google_compute_network.vpc.name
  direction = "EGRESS"
  priority  = 100

  # The metadata server hands the node's service-account token to anything that asks, over
  # plain HTTP, with no authentication beyond being on the box. For a sandbox that is a
  # full credential compromise in one curl. Workload Identity narrows what the token can
  # do; it does not stop the sandbox getting one.
  destination_ranges = [local.metadata_cidr]
  target_tags        = ["sandbox"]

  deny { protocol = "all" }

  description = "Denies 169.254.169.254. Spike A's acceptance criterion is that a sandbox pod cannot reach it."
}

resource "google_compute_firewall" "sandbox_deny_internal" {
  name      = "${local.prefix}-sandbox-deny-internal"
  project   = var.project_id
  network   = google_compute_network.vpc.name
  direction = "EGRESS"
  priority  = 110

  # Everything else in the VPC. A sandbox that can reach the services zone can call an
  # internal API with no token and get whatever that API does not check — and the data
  # zone holds every tenant's data behind nothing but RLS.
  destination_ranges = [
    var.subnets.edge,
    var.subnets.services,
    var.subnets.data,
    var.pods_cidr,
    var.services_cidr,
  ]
  target_tags = ["sandbox"]

  deny { protocol = "all" }

  description = "A sandbox may not reach any other zone. Its only permitted destination is the egress proxy."
}

resource "google_compute_firewall" "sandbox_deny_internet" {
  name               = "${local.prefix}-sandbox-deny-internet"
  project            = var.project_id
  network            = google_compute_network.vpc.name
  direction          = "EGRESS"
  priority           = 120
  destination_ranges = ["0.0.0.0/0"]
  target_tags        = ["sandbox"]

  deny { protocol = "all" }

  description = "No internet from a sandbox. Package installs go through the proxy, which logs and allow-lists them."
}

# The one hole, and it is only a hole once something fills egress_proxy_ip. Priority 90 so
# it precedes the denies above — the only rule in this file that does.
resource "google_compute_firewall" "sandbox_allow_proxy" {
  count = var.egress_proxy_ip == "" ? 0 : 1

  name               = "${local.prefix}-sandbox-allow-proxy"
  project            = var.project_id
  network            = google_compute_network.vpc.name
  direction          = "EGRESS"
  priority           = 90
  destination_ranges = ["${var.egress_proxy_ip}/32"]
  target_tags        = ["sandbox"]

  allow {
    protocol = "tcp"
    ports    = ["3128"]
  }

  description = "The single permitted sandbox destination. Absent until sandbox-controller exists, and while absent a sandbox has no egress at all."
}

# --------------------------------------------------------------------- zone boundaries

resource "google_compute_firewall" "data_deny_egress" {
  name               = "${local.prefix}-data-deny-egress"
  project            = var.project_id
  network            = google_compute_network.vpc.name
  direction          = "EGRESS"
  priority           = 200
  destination_ranges = ["0.0.0.0/0"]
  target_tags        = ["data"]

  deny { protocol = "all" }

  description = "HLD §10.2: the data zone has no egress. A database that can call out is a database that can be made to exfiltrate."
}

resource "google_compute_firewall" "data_allow_from_services" {
  name          = "${local.prefix}-data-allow-from-services"
  project       = var.project_id
  network       = google_compute_network.vpc.name
  direction     = "INGRESS"
  priority      = 210
  source_ranges = [var.subnets.services, var.pods_cidr]
  target_tags   = ["data"]

  allow {
    protocol = "tcp"
    ports    = ["5432", "6379", "9092", "9200"] # Postgres, Redis, Kafka, OpenSearch
  }

  description = "Only the services zone reaches the data zone, and only on the ports it actually uses."
}

resource "google_compute_firewall" "services_allow_from_edge" {
  name          = "${local.prefix}-services-allow-from-edge"
  project       = var.project_id
  network       = google_compute_network.vpc.name
  direction     = "INGRESS"
  priority      = 220
  source_ranges = [var.subnets.edge, var.subnets.services, var.pods_cidr]
  target_tags   = ["services"]

  allow {
    protocol = "tcp"
    ports    = ["8080-8099", "15008"] # service ports, plus ztunnel for Istio ambient
  }

  description = "Ingress to services from the edge and from the mesh."
}

# --------------------------------------------------------------------- health and deny-all

resource "google_compute_firewall" "allow_health_checks" {
  name      = "${local.prefix}-allow-health-checks"
  project   = var.project_id
  network   = google_compute_network.vpc.name
  direction = "INGRESS"
  priority  = 300

  # Google's fixed probe ranges. Without this, load balancers mark every backend unhealthy
  # and nothing serves — a failure that looks like the application and is not.
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["services", "edge"]

  allow {
    protocol = "tcp"
    ports    = ["8080-8099", "9080-9099"]
  }

  description = "Google Cloud health check probes. Deliberately not extended to the sandbox zone."
}

resource "google_compute_firewall" "deny_all_ingress" {
  name          = "${local.prefix}-deny-all-ingress"
  project       = var.project_id
  network       = google_compute_network.vpc.name
  direction     = "INGRESS"
  priority      = 65000
  source_ranges = ["0.0.0.0/0"]

  deny { protocol = "all" }

  description = "Default-deny at the lowest priority. GCP has an implied deny; making it explicit means it appears in the console and in an audit."
}
