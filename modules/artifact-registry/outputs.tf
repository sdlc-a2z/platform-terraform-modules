locals {
  # The subdomain segment Artifact Registry uses per format — not the format name itself:
  # a Python repository is served from -python.pkg.dev, an npm one from -npm.pkg.dev.
  host_segment = { DOCKER = "docker", PYTHON = "python", NPM = "npm" }
}

output "repositories" {
  description = "Repository ids by short name."
  value       = { for k, r in google_artifact_registry_repository.this : k => r.repository_id }
}

output "hosts" {
  description = <<-EOT
    The registry host per repository, e.g. australia-southeast2-docker.pkg.dev for a
    Docker repository, australia-southeast2-python.pkg.dev for a Python one.

    Needed separately from `urls` because `docker login` / `.npmrc` / `pip.conf` take the
    host, while a manifest or an install spec takes the full path.
  EOT
  value = {
    for k, r in google_artifact_registry_repository.this :
    k => "${r.location}-${local.host_segment[r.format]}.pkg.dev"
  }
}

output "urls" {
  description = <<-EOT
    Full path prefix per repository. For DOCKER, append /<image>:<tag> or @<digest>. For
    PYTHON, this is the index URL once /simple/ is appended. For NPM, this is the registry
    URL for `.npmrc`.
  EOT
  value = {
    for k, r in google_artifact_registry_repository.this :
    k => "${r.location}-${local.host_segment[r.format]}.pkg.dev/${r.project}/${r.repository_id}"
  }
}
