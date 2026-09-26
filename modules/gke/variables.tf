variable "project_id" { type = string }
variable "region" { type = string }

variable "environment" {
  description = "dev | test | staging | prod — prefixes every resource name"
  type        = string
}

# Zonal for dev, regional everywhere else (ADR-0007). A regional node pool creates its node
# count *per zone*, so `nodes = 1` on a regional pool is three machines — which is how a
# development cluster reaches nine nodes to run under one vCPU.
variable "zonal_in" {
  description = "A zone name makes the cluster zonal; empty makes it regional across the region."
  type        = string
  default     = ""
}

variable "network" { type = string }
variable "subnetwork" { type = string }

variable "pods_range_name" { type = string }
variable "services_range_name" { type = string }

variable "master_cidr" {
  description = "A /28 for the control plane's own network. Must not overlap any subnet."
  type        = string
}

variable "authorized_networks" {
  description = <<-EOT
    CIDRs permitted to reach the Kubernetes API. Empty means nobody outside the VPC can,
    which is the safe default — the API server is the cluster's front door and a public
    endpoint with no allow-list is an invitation.
  EOT
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "pools" {
  description = <<-EOT
    Node pools. `sandbox = true` turns on GKE Sandbox (gVisor) and taints the pool, so only
    workloads that tolerate it land there.

    `min_nodes = 0` is how the sandbox pool costs nothing when idle — GKE scales it from
    zero and back.
  EOT
  type = map(object({
    machine_type = string
    min_nodes    = number
    max_nodes    = number
    disk_size_gb = optional(number, 50)
    sandbox      = optional(bool, false)
    labels       = optional(map(string), {})
  }))
}

variable "release_channel" {
  description = "RAPID | REGULAR | STABLE. REGULAR trades a few weeks of lag for versions that have been run by other people first."
  type        = string
  default     = "REGULAR"
}

variable "node_service_account" {
  description = <<-EOT
    The identity nodes run as. Deliberately not the default compute service account, which
    holds Editor on the whole project — a pod that escapes its container would inherit it.
    This one should hold only logging, monitoring and Artifact Registry read.
  EOT
  type        = string
}
