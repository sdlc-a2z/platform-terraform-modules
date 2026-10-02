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

variable "subnet_id" {
  description = <<-EOT
    A VPC subnet self-link the cluster's brokers are accessible from — unlike Cloud SQL
    and Memorystore, Google Managed Kafka attaches to a real subnet
    (`gcp_config.access_config.network_configs.subnet`), not the Private Service Access
    range (ADR-0006: it sits inside the VPC, not behind classic peering). The network
    module's `data` subnet, previously unused by anything — its own comment wrongly
    credited it with Cloud SQL/Memorystore's isolation (R0-WS1-004) — is exactly this.
  EOT
  type        = string
}

# No defaults — capacity is a fact about one deployment's load and budget. GCP's own
# minimum: 3 vCPU, memory between 1 and 8 GiB per vCPU.
variable "vcpu_count" {
  description = "Minimum 3 (GCP's own floor for a Managed Kafka cluster)."
  type        = number
}

variable "memory_bytes" {
  description = "Must be between 1 and 8 GiB per vCPU."
  type        = number
}

variable "topics" {
  description = <<-EOT
    LLD §2.4's topic catalogue. Keyed by topic name; `<topic>.dlq` is a per-consumer
    pattern in that table, not a single literal topic, so it is not provisioned here —
    each consumer creates its own when it exists.
  EOT
  type = map(object({
    partition_count = number
    retention_ms    = number
  }))
}
