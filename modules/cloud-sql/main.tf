# One Cloud SQL Postgres 16 instance, REGIONAL (HA) availability, one database and one
# <name>_owner / <name>_app role pair per entry in `var.databases` (LLD §1.4, ADR-0011).
#
# What this module does NOT do, and why: `google_sql_database`/`google_sql_user` are
# Cloud SQL Admin API calls, not SQL. They create a bare database and two login roles, but
# the Admin API — not any Postgres role — ends up owning each database, so `<name>_owner`
# cannot actually create a table in "its own" database yet. That one GRANT per database
# (`GRANT CREATE ON SCHEMA public TO "<name>_owner"`) needs a live SQL connection to a
# private IP nothing outside the VPC can reach — CI included — so it is a one-time,
# operator-run step against the cluster, not a Terraform resource. See this repository's
# README / the story's spec for the exact command. `<name>_app` needs no equivalent grant:
# Postgres 16 does not grant CREATE on the public schema to a non-owner role by default.

resource "google_sql_database_instance" "main" {
  name                = "${var.environment}-aisdlc"
  project             = var.project_id
  region              = var.region
  database_version    = "POSTGRES_16"
  deletion_protection = var.environment == "prod"

  settings {
    tier = var.tier

    # Without this, the provider defaults to ENTERPRISE_PLUS — found live
    # ("Invalid Tier (db-custom-2-7680) for (ENTERPRISE_PLUS) Edition. Use a predefined
    # Tier like db-perf-optimized-N-* instead"), not documented anywhere as a default
    # worth knowing. ENTERPRISE_PLUS is Google's newer, pricier edition (data cache,
    # near-zero-downtime updates); ENTERPRISE is the classic db-custom-N-M tier shape and
    # matches ADR-0007's "minimally sized dev" — this platform has no feature that needs
    # what the newer edition adds.
    edition = "ENTERPRISE"

    # REGIONAL, not ZONAL (ADR-0011): a synchronous standby in a second zone, automatic
    # failover. Costs roughly double a single-zone instance — accepted because the
    # per-service schema and role split is a permanent decision worth getting right once
    # across sixteen databases, not because dev traffic needs the uptime yet.
    availability_type = "REGIONAL"

    disk_autoresize = true

    # No public IP anywhere. The only path to this instance is from inside the VPC, on the
    # Private Service Access range the network module peers — enforced by
    # `services_allow_to_psa_data` (network module), not by this setting alone.
    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
    }

    backup_configuration {
      enabled    = true
      start_time = "16:00" # 02:00 AEDT — outside Melbourne business hours.
    }
  }
}

# The instance's own admin login. Cloud SQL's default "postgres" user always exists; this
# just gives it a known password instead of Google's own auto-generated one, so the
# one-time GRANT step (see this file's header) can authenticate.
resource "random_password" "admin" {
  length  = 32
  special = false # the password crosses a shell (the one-time bootstrap command) at least once
}

resource "google_sql_user" "admin" {
  name     = "postgres"
  project  = var.project_id
  instance = google_sql_database_instance.main.name
  password = random_password.admin.result
}

resource "google_secret_manager_secret" "admin_password" {
  secret_id = "${var.environment}-cloudsql-admin-password"
  project   = var.project_id
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "admin_password" {
  secret      = google_secret_manager_secret.admin_password.id
  secret_data = random_password.admin.result
}

resource "google_sql_database" "this" {
  for_each = var.databases
  name     = "${each.key}_db"
  project  = var.project_id
  instance = google_sql_database_instance.main.name
}

resource "random_password" "owner" {
  for_each = var.databases
  length   = 32
  special  = false
}

resource "random_password" "app" {
  for_each = var.databases
  length   = 32
  special  = false
}

resource "google_sql_user" "owner" {
  for_each = var.databases
  name     = "${each.key}_owner"
  project  = var.project_id
  instance = google_sql_database_instance.main.name
  password = random_password.owner[each.key].result
}

resource "google_sql_user" "app" {
  for_each = var.databases
  name     = "${each.key}_app"
  project  = var.project_id
  instance = google_sql_database_instance.main.name
  password = random_password.app[each.key].result
}

# One DSN per role per database, not one shared admin DSN handed to every service: a
# compromised service can do no more than its own `_app` role already could.
resource "google_secret_manager_secret" "owner_dsn" {
  for_each  = var.databases
  secret_id = "${var.environment}-${each.key}-db-owner-dsn"
  project   = var.project_id
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "owner_dsn" {
  for_each = var.databases
  secret   = google_secret_manager_secret.owner_dsn[each.key].id
  secret_data = join("", [
    "postgresql://${each.key}_owner:${random_password.owner[each.key].result}",
    "@${google_sql_database_instance.main.private_ip_address}:5432/${each.key}_db",
  ])
}

resource "google_secret_manager_secret" "app_dsn" {
  for_each  = var.databases
  secret_id = "${var.environment}-${each.key}-db-app-dsn"
  project   = var.project_id
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "app_dsn" {
  for_each = var.databases
  secret   = google_secret_manager_secret.app_dsn[each.key].id
  secret_data = join("", [
    "postgresql://${each.key}_app:${random_password.app[each.key].result}",
    "@${google_sql_database_instance.main.private_ip_address}:5432/${each.key}_db",
  ])
}
