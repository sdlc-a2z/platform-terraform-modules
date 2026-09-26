# Firewall. This file is the network zone boundary from HLD §10.2.
#
# GCP evaluates by priority, lowest number first, and stops at the first match. So the
# denies that matter sit at low numbers and the allows sit above them: a later "allow all
# egress" cannot undo an earlier deny. Getting that order wrong is silent — everything
# still works, and the control is simply absent.

# --------------------------------------------------------------------- sandbox egress
#
# These rules apply to the *node*, because a VPC firewall filters nodes — a pod shares its
# node's network stack and tags. The pod's own egress is a NetworkPolicy, and both layers
# are required (ADR-0008).
#
# The first version of this file denied everything from the `sandbox` tag, which is
# correct for a pod and fatal for a node: the node could not reach the GKE control plane
# to register, was recreated several times, and the pool gave up. The rules worked; the
# design did not.
#
# So: a node gets exactly what it needs to join and nothing else. Priorities stay low so
# no later allow can undo them.

resource "google_compute_firewall" "sandbox_allow_control_plane" {
  name      = "${local.prefix}-sandbox-allow-control-plane"
  project   = var.project_id
  network   = google_compute_network.vpc.name
  direction = "EGRESS"
  priority  = 90

  # Without this the kubelet cannot register and the node is destroyed and recreated
  # forever. It is the narrowest of the three allows — one /28, one port.
  destination_ranges = [var.master_cidr]
  target_tags        = ["sandbox"]

  allow {
    protocol = "tcp"
    ports    = ["443", "10250"]
  }

  description = "The GKE control plane. A node that cannot reach it never joins."
}

resource "google_compute_firewall" "sandbox_allow_google_apis" {
  name      = "${local.prefix}-sandbox-allow-google-apis"
  project   = var.project_id
  network   = google_compute_network.vpc.name
  direction = "EGRESS"
  priority  = 91

  # private.googleapis.com only — not the whole internet, and not the public API IPs.
  # Image pulls, logging and monitoring go here. A pod cannot use it: the NetworkPolicy
  # denies pod egress, and Workload Identity means a pod's token is not the node's.
  destination_ranges = ["199.36.153.8/30"]
  target_tags        = ["sandbox"]

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  description = "Private Google Access, for image pulls and telemetry. Node only; pods are denied by NetworkPolicy."
}

resource "google_compute_firewall" "sandbox_allow_metadata_dns_ntp" {
  name      = "${local.prefix}-sandbox-allow-metadata-dns-ntp"
  project   = var.project_id
  network   = google_compute_network.vpc.name
  direction = "EGRESS"
  priority  = 92

  # DNS and NTP only. Deliberately NOT port 80, which is where the metadata server hands
  # out credentials — that stays denied at priority 100 below.
  #
  # A node needs name resolution and time; without time, TLS to the control plane fails in
  # a way that looks like anything but a clock.
  destination_ranges = [local.metadata_cidr]
  target_tags        = ["sandbox"]

  allow {
    protocol = "tcp"
    ports    = ["53"]
  }
  allow {
    protocol = "udp"
    ports    = ["53", "123"]
  }

  description = "DNS and NTP from the metadata server. Port 80 — the credentials endpoint — stays denied."
}

resource "google_compute_firewall" "sandbox_deny_metadata" {
  name      = "${local.prefix}-sandbox-deny-metadata"
  project   = var.project_id
  network   = google_compute_network.vpc.name
  direction = "EGRESS"
  priority  = 100

  # The credentials endpoint. It hands the node's service-account token to anything that
  # asks, over plain HTTP, with no authentication beyond being on the box. Denied at a
  # higher number than the DNS allow above, so 53 and 123 survive and 80 does not.
  destination_ranges = [local.metadata_cidr]
  target_tags        = ["sandbox"]

  deny { protocol = "tcp" }

  description = "Denies the metadata credentials endpoint. Spike A's acceptance criterion is that a sandbox pod cannot reach 169.254.169.254."
}

resource "google_compute_firewall" "sandbox_deny_internal" {
  name      = "${local.prefix}-sandbox-deny-internal"
  project   = var.project_id
  network   = google_compute_network.vpc.name
  direction = "EGRESS"
  priority  = 110

  # Every other zone. A sandbox reaching the services zone can call an internal API with no
  # token; the data zone holds every tenant's data behind nothing but RLS.
  #
  # The pod CIDR is excluded: kube-dns and the node's own pods live there, and a node that
  # cannot resolve in-cluster names cannot run anything. Pod-to-pod egress is denied by the
  # NetworkPolicy instead, which is the layer that can tell a sandbox pod from kube-dns.
  destination_ranges = [
    var.subnets.edge,
    var.subnets.services,
    var.subnets.data,
  ]
  target_tags = ["sandbox"]

  deny { protocol = "all" }

  description = "No other zone. Pod-to-pod is handled by NetworkPolicy, which can distinguish a sandbox pod from kube-dns."
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

  description = "No internet. Package installs go through the proxy, which logs and allow-lists them."
}

# The one hole for pods, and it only exists once something fills egress_proxy_ip.
resource "google_compute_firewall" "sandbox_allow_proxy" {
  count = var.egress_proxy_ip == "" ? 0 : 1

  name               = "${local.prefix}-sandbox-allow-proxy"
  project            = var.project_id
  network            = google_compute_network.vpc.name
  direction          = "EGRESS"
  priority           = 95
  destination_ranges = ["${var.egress_proxy_ip}/32"]
  target_tags        = ["sandbox"]

  allow {
    protocol = "tcp"
    ports    = ["3128"]
  }

  description = "The single permitted sandbox destination. Absent until sandbox-controller exists."
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
