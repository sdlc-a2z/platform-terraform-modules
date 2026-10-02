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
    The VPC's self-link. The instance's private IP is drawn from the Private Service
    Access range peered to this network, not from any subnet in it — see the network
    module's own `psa_range` for why.
  EOT
  type        = string
}

# No default. A machine tier is a fact about one deployment's traffic and budget, not
# about the pattern — same reasoning `subnets` and `psa_range` give in the network module.
variable "tier" {
  description = "Cloud SQL machine tier, e.g. db-custom-2-7680."
  type        = string
}

variable "databases" {
  description = <<-EOT
    Short per-service names (LLD §1.4's naming, not necessarily the service's own name —
    e.g. "evaluation-service" is "eval", "agent-registry" is "registry"). Each name
    becomes one database, `<name>_db`, and two roles: `<name>_owner` (DDL rights, granted
    CREATE on the public schema — see main.tf's header for why that one grant is not a
    Terraform resource) and `<name>_app` (no DDL rights; Postgres 16 does not grant CREATE
    on the public schema to a non-owner role by default, so this needs no explicit
    REVOKE). One Cloud SQL instance, one database per service, never shared — HLD §9.2's
    "database per service" is a tenancy boundary, not a suggestion.
  EOT
  type        = set(string)
}
