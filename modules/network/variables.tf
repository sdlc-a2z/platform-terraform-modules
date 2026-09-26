variable "project_id" {
  description = "GCP project this network lives in"
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

# Zones are subnets in one VPC rather than separate VPCs. Peering four VPCs to let the
# services zone reach the data zone would cost the isolation this design is for: peering
# is transitive-by-accident and its firewall story is worse than one VPC with strict
# rules. The isolation here is enforced by firewall and by tags, both of which are
# readable in one place.
# No defaults. This repository is public, and an address plan is a fact about a specific
# deployment rather than about the pattern — so the numbers live in the environment, which
# is private. Requiring them also stops a second environment silently inheriting the
# first's ranges and colliding on a future peering.
variable "subnets" {
  description = <<-EOT
    Zone CIDRs (HLD §10.2). The sandbox range is deliberately separate: nothing in it may
    reach anything except the egress proxy.
  EOT
  type = object({
    edge     = string
    services = string
    data     = string
    sandbox  = string
  })
}

variable "pods_cidr" {
  description = "Secondary range for GKE pods"
  type        = string
}

variable "services_cidr" {
  description = "Secondary range for GKE services"
  type        = string
}

variable "egress_proxy_ip" {
  description = <<-EOT
    The one address a sandbox may reach. Empty until sandbox-controller exists
    (R0-WS3-003), and while it is empty the sandbox subnet has no permitted egress at
    all — which is the safe direction to be wrong in.
  EOT
  type        = string
  default     = ""
}

variable "master_cidr" {
  description = <<-EOT
    The GKE control plane's /28. A sandbox node must reach it on 443 or the kubelet never
    registers — which is how the first version of this module produced a node pool that
    could not scale.
  EOT
  type        = string
}
