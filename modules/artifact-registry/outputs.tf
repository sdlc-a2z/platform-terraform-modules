output "repositories" {
  description = "Repository ids by short name."
  value       = { for k, r in google_artifact_registry_repository.this : k => r.repository_id }
}

output "hosts" {
  description = <<-EOT
    The registry host per repository, e.g. australia-southeast2-docker.pkg.dev.

    Needed separately from `urls` because `docker login` and a pod's imagePullSecret take
    the host, while a manifest takes the full path.
  EOT
  value       = { for k, r in google_artifact_registry_repository.this : k => "${r.location}-docker.pkg.dev" }
}

output "urls" {
  description = "Full image path prefix per repository — append /<image>:<tag> or @<digest>."
  value = {
    for k, r in google_artifact_registry_repository.this :
    k => "${r.location}-docker.pkg.dev/${r.project}/${r.repository_id}"
  }
}
