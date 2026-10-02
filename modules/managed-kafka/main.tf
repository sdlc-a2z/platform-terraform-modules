# One Google Managed Kafka cluster (ADR-0006), with the topic catalogue LLD §2.4 names.
#
# No Schema Registry resource here, and that is a real gap, not an oversight: as of this
# module, Managed Kafka's Schema Registry is only reachable through `gcloud beta
# managed-kafka schema-registries` — it does not exist in either the stable `google`
# provider or `google-beta` (confirmed against this module's own provider version by
# listing every `*kafka*`/`*schema_registry*` resource both expose; neither has one).
# ADR-0006 already frames the registry as "a runtime guard rather than the source of
# truth" — platform-contracts/Buf owns schema evolution — so this is deferred rather than
# reached for with a manual, unreproducible gcloud step for a guard nothing yet depends on.
# No acceptance criterion in R0-WS1-004 tests it either.
#
# No ACLs: Kafka's per-principal authorization needs a real producer/consumer identity to
# scope to, and none exists yet — every topic here currently has zero producers or
# consumers, matching Cloud SQL's equivalent decision not to wire `<name>_app` grants a
# migration will someday need.

resource "google_managed_kafka_cluster" "main" {
  cluster_id = "${var.environment}-aisdlc"
  project    = var.project_id
  location   = var.region

  capacity_config {
    vcpu_count   = var.vcpu_count
    memory_bytes = var.memory_bytes
  }

  gcp_config {
    access_config {
      network_configs {
        subnet = var.subnet_id
      }
    }
  }
}

resource "google_managed_kafka_topic" "this" {
  for_each = var.topics

  cluster  = google_managed_kafka_cluster.main.cluster_id
  topic_id = each.key
  location = var.region
  project  = var.project_id

  partition_count = each.value.partition_count
  # 3, not a variable: GCP's minimum for a cluster this small, and nothing about a topic's
  # own retention or partition count changes that floor.
  replication_factor = 3

  configs = {
    "retention.ms" = tostring(each.value.retention_ms)
  }
}
