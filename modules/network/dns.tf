# Private DNS for Google's APIs (ADR-0009).
#
# Private Google Access makes 199.36.153.8/30 routable. It does not change what a name
# resolves to — so without these zones a node looks up `australia-southeast2-docker.pkg.dev`,
# gets its public address, and `sandbox-deny-internet` denies it at priority 120. PGA on,
# and still no image.
#
# Two zones, not one. Artifact Registry is served from `pkg.dev`, which is a separate
# domain from `googleapis.com` and is the piece most often missed — the symptom is a node
# that can reach Cloud Logging and cannot pull an image, which reads as a registry
# permissions problem.

locals {
  # private.googleapis.com. The stricter restricted.googleapis.com is 199.36.153.4/30 and
  # is not used here: it serves only APIs a VPC Service Controls perimeter can constrain,
  # and there is no perimeter yet. ADR-0009 revisits it with one.
  private_api_vip = ["199.36.153.8", "199.36.153.9", "199.36.153.10", "199.36.153.11"]

  # Three domains, and the third is the one that actually stopped the cluster.
  #
  # `googleapis.com` covers the APIs, including storage, which is what a registry's layers
  # are served from. `pkg.dev` is Artifact Registry, where our own images live.
  #
  # `gcr.io` is where GKE's *own* system images come from — the `pause` container, anetd,
  # netd, the metadata server, fluentbit. Without it a node joins, reports NotReady, and
  # every system pod sits in `Init:0/n` with `dial tcp 192.178.230.82:443: i/o timeout`:
  # a public address, because the name resolved publicly, denied by `deny-internet`. The
  # error names the image and says nothing about DNS. Adding two zones and missing this
  # one buys a node that is worse than the one that could not scale, because it looks
  # like it nearly worked.
  api_zones = {
    googleapis = { domain = "googleapis.com.", description = "Google APIs over Private Google Access" }
    pkgdev     = { domain = "pkg.dev.", description = "Artifact Registry over Private Google Access" }
    gcrio      = { domain = "gcr.io.", description = "GKE system images over Private Google Access" }
  }
}

resource "google_dns_managed_zone" "private_apis" {
  for_each = local.api_zones

  project     = var.project_id
  name        = "${local.prefix}-${each.key}"
  dns_name    = each.value.domain
  description = each.value.description
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.vpc.id
    }
  }
}

# The apex. `googleapis.com` and `pkg.dev` themselves have to answer, not only their
# subdomains: a wildcard does not cover the zone apex, and some clients resolve the bare
# name first.
resource "google_dns_record_set" "apex" {
  for_each = local.api_zones

  project      = var.project_id
  managed_zone = google_dns_managed_zone.private_apis[each.key].name
  name         = each.value.domain
  type         = "A"
  ttl          = 300
  rrdatas      = local.private_api_vip
}

# Everything under it. A wildcard rather than a record per service: the alternative is
# discovering a missing name at the moment something breaks, which for a private zone
# means a public IP the firewall then denies.
resource "google_dns_record_set" "wildcard" {
  for_each = local.api_zones

  project      = var.project_id
  managed_zone = google_dns_managed_zone.private_apis[each.key].name
  name         = "*.${each.value.domain}"
  type         = "CNAME"
  ttl          = 300
  rrdatas      = [each.value.domain]
}
