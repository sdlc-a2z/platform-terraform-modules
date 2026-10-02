# One Memorystore Redis instance, shared across every consumer (HLD §9.2 says "database
# per service" for Postgres specifically; it says nothing equivalent for Redis, and every
# current consumer — cost-service, insights-service, llm-router, realtime-gateway — uses
# it for caches, budget counters, rate limits and SSE fan-out, none of it tenant-record
# data the way a Postgres table is). Logical separation is by key prefix (`<service>:...`),
# a convention each consuming service owns, not something this module can enforce the way
# `<name>_db` gives each Postgres consumer a real, separate, access-controlled database.
#
# One shared AUTH secret, not one per service, because Memorystore has no per-connection
# login the way Postgres has `<name>_owner`/`<name>_app` — `auth_enabled` protects the
# whole instance with a single string. Splitting it into per-service Secret Manager
# entries would imply a security boundary between services that does not actually exist
# at the Redis layer.

resource "google_redis_instance" "main" {
  name           = "${var.environment}-aisdlc"
  project        = var.project_id
  region         = var.region
  tier           = var.tier
  memory_size_gb = var.memory_size_gb
  redis_version  = "REDIS_7_2"

  authorized_network = var.network_id
  connect_mode       = "PRIVATE_SERVICE_ACCESS"

  auth_enabled = true
}

resource "google_secret_manager_secret" "redis_url" {
  secret_id = "${var.environment}-redis-url"
  project   = var.project_id
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "redis_url" {
  secret = google_secret_manager_secret.redis_url.id
  secret_data = join("", [
    "redis://:${google_redis_instance.main.auth_string}",
    "@${google_redis_instance.main.host}:${google_redis_instance.main.port}",
  ])
}
