output "repository_ids" {
  description = "Map of repository key => repository_id."
  value       = { for k, r in google_artifact_registry_repository.this : k => r.repository_id }
}

output "repository_names" {
  description = "Map of repository key => full resource name (projects/.../locations/.../repositories/...)."
  value       = { for k, r in google_artifact_registry_repository.this : k => r.id }
}

output "repository_urls" {
  description = "Map of repository key => registry host/path (e.g. us-central1-docker.pkg.dev/<project>/<repo>) — docker tag / npm registry target. Only meaningful for formats served from *.pkg.dev (DOCKER, MAVEN, NPM, PYTHON, APT, YUM, GO); GENERIC repositories use the artifactregistry.googleapis.com upload/download API and yield null."
  value = {
    for k, r in google_artifact_registry_repository.this :
    k => contains(["DOCKER", "MAVEN", "NPM", "PYTHON", "APT", "YUM", "GO"], r.format) ? "${var.location}-${lower(r.format)}.pkg.dev/${var.project_id}/${r.repository_id}" : null
  }
}
