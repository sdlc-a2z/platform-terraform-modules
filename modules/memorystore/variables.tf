variable "project_id" {
  description = "GCP project id"
  type        = string
}

variable "region" {
  description = "Region. australia-southeast2 (Melbourne) per HLD §11.1."
  type        = string
}

variable "environment" {
  description = "dev | test | staging | prod — prefixes every resource name"
  type        = string
}

variable "network_id" {
  description = <<-EOT
    The VPC's self-link. Like Cloud SQL, Memorystore's private IP comes from the Private
    Service Access range peered to this network (cloud-sql module's `psa_range`), via
    `connect_mode = PRIVATE_SERVICE_ACCESS` — the same peering connection, not a second
    one.
  EOT
  type        = string
}

# No defaults — size and tier are facts about one deployment's load and budget, not the
# pattern, same reasoning the cloud-sql module gives for `tier`.
variable "memory_size_gb" {
  description = "Instance capacity in GiB."
  type        = number
}

variable "tier" {
  description = <<-EOT
    "BASIC" (single node, no replica) or "STANDARD_HA" (replica, automatic failover).
    HLD §9.2 does not ask for HA on Redis the way it does for Postgres — every current
    consumer (cost-service, insights-service, llm-router, realtime-gateway) uses it for
    caches, rate limits and SSE fan-out: state that is rebuildable, not a record of truth.
  EOT
  type        = string
}
