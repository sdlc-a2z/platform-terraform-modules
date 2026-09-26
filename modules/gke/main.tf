# The GKE cluster and its node pools.
#
# Node pools are separate resources rather than inline, because an inline pool forces the
# whole cluster to be replaced when it changes — and replacing a cluster means replacing
# everything running on it.

locals {
  name = "${var.environment}-aisdlc"

  # A zone makes it zonal, the region makes it regional. GKE infers which from the value.
  location = var.zonal_in != "" ? var.zonal_in : var.region
}

resource "google_container_cluster" "cluster" {
  provider = google-beta

  name     = local.name
  project  = var.project_id
  location = local.location

  network    = var.network
  subnetwork = var.subnetwork

  # GKE insists on a node pool at creation and then wants it managed separately. Creating
  # the default and immediately removing it is the documented way through.
  remove_default_node_pool = true
  initial_node_count       = 1

  # Deletion protection off in every environment, including prod. The protection that
  # matters is a reviewed plan and a PR; a flag that makes `terraform destroy` fail is
  # worked around by the person who most wanted to destroy it.
  deletion_protection = false

  release_channel {
    channel = var.release_channel
  }

  # VPC-native. Routes-based clusters cannot use network policy or Private Google Access
  # properly, and the secondary ranges are what let pods be addressable without NAT.
  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  private_cluster_config {
    # Nodes have no public addresses. They reach the internet through Cloud NAT, which is
    # scoped to exclude the sandbox subnet — so a sandbox node has no route out at all.
    enable_private_nodes = true
    # The control plane keeps a public endpoint, gated by authorized_networks below.
    # Turning it off entirely requires a bastion or VPN to run kubectl, which R0 does not
    # have; the allow-list is the control until it does.
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_cidr
  }

  dynamic "master_authorized_networks_config" {
    for_each = length(var.authorized_networks) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }

  # Workload Identity: a pod authenticates to Google as a Kubernetes service account, with
  # no key anywhere. Without it the alternative is a service-account key in a secret, which
  # is the thing HLD §10.3 forbids.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Shielded nodes: secure boot and integrity monitoring, so a node that has been tampered
  # with fails to join rather than joining quietly.
  enable_shielded_nodes = true

  # Dataplane V2 (eBPF) rather than Calico. It carries network policy without a per-node
  # agent, and its flow logs are what make a denied connection visible.
  datapath_provider = "ADVANCED_DATAPATH"

  addons_config {
    # Istio ambient provides the mesh; the GKE add-on would fight it.
    http_load_balancing { disabled = false }
    horizontal_pod_autoscaling { disabled = false }
    # KEDA is installed by Argo, not as an add-on, so its version is in git.
    gcp_filestore_csi_driver_config { enabled = false }
  }

  # Secrets are encrypted at rest by default; this is about the audit trail of who read
  # what, which the audit pipeline (ADR-0001) depends on.
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus { enabled = true }
  }

  # Upgrades during a window rather than whenever. A surprise node upgrade mid-job kills
  # running sandboxes.
  maintenance_policy {
    recurring_window {
      start_time = "2026-01-01T14:00:00Z" # 01:00 Melbourne
      end_time   = "2026-01-01T18:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=TU,WE,TH"
    }
  }

  lifecycle {
    # The node count on the removed default pool drifts; ignoring it stops every plan
    # proposing a change nobody made.
    ignore_changes = [initial_node_count]
  }
}

resource "google_container_node_pool" "pools" {
  provider = google-beta

  for_each = var.pools

  name     = each.key
  project  = var.project_id
  location = local.location
  cluster  = google_container_cluster.cluster.name

  # On a regional cluster this is nodes *per zone*, so the true count is three times this.
  # ADR-0007 is why dev is zonal.
  initial_node_count = each.value.min_nodes

  autoscaling {
    min_node_count = each.value.min_nodes
    max_node_count = each.value.max_nodes
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type = each.value.machine_type
    disk_size_gb = each.value.disk_size_gb
    disk_type    = "pd-balanced"

    # Container-Optimized OS with containerd. Required for GKE Sandbox, and it has no
    # package manager for a compromised process to use.
    image_type = "COS_CONTAINERD"

    # The node's own identity carries nothing. Workload Identity gives pods their
    # permissions, so a pod that escapes to the node gains no cloud access.
    service_account = var.node_service_account
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      # GKE_METADATA replaces the node's metadata server with one that refuses to hand out
      # the node identity. Belt to the firewall's braces: the firewall denies the address,
      # this denies the answer.
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = merge(each.value.labels, {
      pool        = each.key
      environment = var.environment
    })

    # The network tag the firewall rules select on. Without it a sandbox node is not
    # matched by sandbox-deny-metadata and has ordinary egress.
    tags = [each.key, var.environment]

    dynamic "sandbox_config" {
      for_each = each.value.sandbox ? [1] : []
      content {
        sandbox_type = "gvisor"
      }
    }

    dynamic "taint" {
      # gVisor pools are tainted so only workloads that opt in land there. GKE adds its own
      # sandbox taint too; this one is ours and is what the sandbox-controller tolerates.
      for_each = each.value.sandbox ? [1] : []
      content {
        key    = "sandbox"
        value  = "true"
        effect = "NO_SCHEDULE"
      }
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  lifecycle {
    # The autoscaler owns the count after creation.
    ignore_changes = [initial_node_count, node_config[0].taint]
  }
}
