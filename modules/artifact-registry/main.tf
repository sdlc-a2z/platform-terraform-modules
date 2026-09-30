# Package registry, one repository per format this platform publishes.
#
# Started Docker-only: the sandbox node pool has no internet and no NAT, and its only route
# off the node is 199.36.153.8/30 — `restricted.googleapis.com` — so the image registry it
# pulls from has to be a Google API rather than Docker Hub, ghcr.io or anything else
# (ADR-0009). R0-WS2-008 / ADR-0010 added PYTHON and NPM: the generated Python and
# TypeScript clients are private to this org, and this project already has the registry,
# the IAM pattern and the CI identity a public PyPI/npm account would have needed from
# scratch.

resource "google_artifact_registry_repository" "this" {
  for_each = var.repositories

  project       = var.project_id
  location      = var.region
  repository_id = "${var.environment}-${each.key}"
  description   = each.value.description
  format        = each.value.format

  # Immutable tags. A tag that can be moved means the image running in the cluster can
  # change with no commit saying so, which defeats both the signature and the audit trail.
  # Deployments pull by digest anyway; this stops the tag lying in the meantime.
  #
  # Docker-only: `docker_config` is rejected by the API on a Python or npm repository, and
  # tag mutability is not a solved concept for either format the way it is for an image.
  dynamic "docker_config" {
    for_each = each.value.format == "DOCKER" ? [1] : []
    content {
      immutable_tags = true
    }
  }

  dynamic "cleanup_policies" {
    for_each = each.value.keep_untagged_days == null ? [] : [1]
    content {
      id     = "delete-untagged"
      action = "DELETE"
      condition {
        tag_state  = "UNTAGGED"
        older_than = "${each.value.keep_untagged_days * 24}h"
      }
    }
  }

  # Keep the most recent releases regardless of age, so a cleanup policy can never delete
  # the image a running deployment is pinned to.
  dynamic "cleanup_policies" {
    for_each = each.value.keep_untagged_days == null ? [] : [1]
    content {
      id     = "keep-recent"
      action = "KEEP"
      most_recent_versions {
        keep_count = 20
      }
    }
  }

  labels = {
    environment = var.environment
    managed-by  = "terraform"
  }
}

# Who may pull.
#
# Granted per repository rather than at project level: a node pool that pulls sandbox
# images has no reason to read the platform's service images, and `roles/artifactregistry.reader`
# at the project is the kind of convenience grant that is never narrowed afterwards.
resource "google_artifact_registry_repository_iam_member" "readers" {
  for_each = local.reader_bindings

  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.this[each.value.repository].name
  role       = "roles/artifactregistry.reader"
  member     = each.value.member
}

# Who may push. Deliberately separate from the readers, and deliberately `writer` rather
# than `admin`: CI needs to add a version, never to delete one or change the policy.
resource "google_artifact_registry_repository_iam_member" "writers" {
  for_each = local.writer_bindings

  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.this[each.value.repository].name
  role       = "roles/artifactregistry.writer"
  member     = each.value.member
}

locals {
  reader_bindings = {
    for pair in flatten([
      for name, cfg in var.repositories : [
        for member in cfg.readers : {
          repository = name
          member     = member
        }
      ]
    ]) : "${pair.repository}/${pair.member}" => pair
  }

  writer_bindings = {
    for pair in flatten([
      for name, cfg in var.repositories : [
        for member in cfg.writers : {
          repository = name
          member     = member
        }
      ]
    ]) : "${pair.repository}/${pair.member}" => pair
  }
}
