variable "project_id" {
  description = "GCP project the registries live in"
  type        = string
}

variable "region" {
  description = "Region. Must match the cluster's, or every pull crosses regions and is billed for it."
  type        = string
}

variable "environment" {
  description = "dev | test | staging | prod — prefixes every repository name"
  type        = string
}

# No default. This repository is public, and a member list is a fact about one deployment
# rather than about the pattern — the same reason the network module takes its CIDRs as
# inputs. It also stops a second environment silently granting the first's accounts.
variable "repositories" {
  description = <<-EOT
    Registries to create, keyed by short name. The full id is "<environment>-<key>".

    `readers` and `writers` are fully-qualified IAM members ("serviceAccount:...").
    Granted per repository, never at project level: a node pool that pulls sandbox images
    has no reason to read service images.

    `keep_untagged_days` null disables cleanup entirely. Set it and the module also keeps
    the 20 most recent versions unconditionally, so a policy cannot delete the image a
    running deployment is pinned to.
  EOT

  type = map(object({
    description        = string
    format             = optional(string, "DOCKER")
    readers            = optional(list(string), [])
    writers            = optional(list(string), [])
    keep_untagged_days = optional(number, null)
  }))

  validation {
    condition     = alltrue([for k in keys(var.repositories) : can(regex("^[a-z][a-z0-9-]{1,40}$", k))])
    error_message = "Repository keys must be lowercase alphanumeric with hyphens, 2-41 characters."
  }

  validation {
    # The formats this platform has an actual use for, not GAR's full list (APT, YUM,
    # KFP, Maven also exist). Narrower on purpose: a typo like "Python" fails here instead
    # of a confusing 400 from the API, and a format nothing here consumes is one nobody
    # has thought through the cleanup-policy or IAM implications of.
    condition = alltrue([
      for cfg in values(var.repositories) : contains(["DOCKER", "PYTHON", "NPM"], cfg.format)
    ])
    error_message = "format must be one of DOCKER, PYTHON, NPM."
  }

  validation {
    condition = alltrue(flatten([
      for cfg in values(var.repositories) : [
        for m in concat(cfg.readers, cfg.writers) :
        can(regex("^(serviceAccount|user|group|principalSet|principal):", m))
      ]
    ]))
    error_message = "Members must be fully qualified, e.g. serviceAccount:ci@project.iam.gserviceaccount.com. A bare email is accepted by the API as a user and silently grants the wrong principal."
  }
}
