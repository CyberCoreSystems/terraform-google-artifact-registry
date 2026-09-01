# Artifact Registry repositories — standard, remote (public-upstream proxy)
# and virtual (aggregating) modes — with cleanup policies, immutable Docker
# tags, optional CMEK and least-privilege reader/writer IAM.
# Works with Terraform and OpenTofu.

locals {
  # "<repo_key>|<member>" => reader binding, flattened across repositories.
  reader_bindings = merge([
    for repo_key, repo in var.repositories : {
      for member in repo.reader_members : "${repo_key}|${member}" => {
        repo_key = repo_key
        member   = member
      }
    }
  ]...)

  # "<repo_key>|<member>" => writer binding.
  writer_bindings = merge([
    for repo_key, repo in var.repositories : {
      for member in repo.writer_members : "${repo_key}|${member}" => {
        repo_key = repo_key
        member   = member
      }
    }
  ]...)

  # Virtual-repo upstreams may name a sibling repository by key; anything
  # containing "/" is treated as a full repository resource path.
  resolved_upstreams = {
    for repo_key, repo in var.repositories : repo_key => [
      for upstream in repo.virtual_upstreams : {
        id       = upstream.id
        priority = upstream.priority
        repository = (
          strcontains(upstream.repository, "/")
          ? upstream.repository
          : "projects/${var.project_id}/locations/${var.location}/repositories/${upstream.repository}"
        )
      }
    ]
  }
}

resource "google_artifact_registry_repository" "this" {
  for_each = var.repositories

  project       = var.project_id
  location      = var.location
  repository_id = each.key
  format        = each.value.format
  mode          = each.value.mode
  description   = each.value.description
  kms_key_name  = each.value.kms_key_name
  labels        = merge(var.labels, each.value.labels)

  cleanup_policy_dry_run = each.value.cleanup_policy_dry_run

  # Immutable tags by default: a pushed tag can never silently change image.
  dynamic "docker_config" {
    for_each = each.value.format == "DOCKER" && each.value.mode == "STANDARD_REPOSITORY" ? [1] : []
    content {
      immutable_tags = each.value.docker_immutable_tags
    }
  }

  dynamic "cleanup_policies" {
    for_each = each.value.cleanup_policies
    content {
      id     = cleanup_policies.key
      action = cleanup_policies.value.action

      dynamic "condition" {
        for_each = cleanup_policies.value.condition == null ? [] : [cleanup_policies.value.condition]
        content {
          tag_state             = condition.value.tag_state
          tag_prefixes          = condition.value.tag_prefixes
          package_name_prefixes = condition.value.package_name_prefixes
          older_than            = condition.value.older_than
          newer_than            = condition.value.newer_than
        }
      }

      dynamic "most_recent_versions" {
        for_each = cleanup_policies.value.most_recent_versions == null ? [] : [cleanup_policies.value.most_recent_versions]
        content {
          package_name_prefixes = most_recent_versions.value.package_name_prefixes
          keep_count            = most_recent_versions.value.keep_count
        }
      }
    }
  }

  # Remote (pull-through proxy) of a well-known public upstream.
  dynamic "remote_repository_config" {
    for_each = each.value.mode == "REMOTE_REPOSITORY" && each.value.remote != null ? [each.value.remote] : []
    content {
      description = remote_repository_config.value.description

      dynamic "docker_repository" {
        for_each = each.value.format == "DOCKER" ? [1] : []
        content {
          public_repository = remote_repository_config.value.public_upstream
        }
      }

      dynamic "maven_repository" {
        for_each = each.value.format == "MAVEN" ? [1] : []
        content {
          public_repository = remote_repository_config.value.public_upstream
        }
      }

      dynamic "npm_repository" {
        for_each = each.value.format == "NPM" ? [1] : []
        content {
          public_repository = remote_repository_config.value.public_upstream
        }
      }

      dynamic "python_repository" {
        for_each = each.value.format == "PYTHON" ? [1] : []
        content {
          public_repository = remote_repository_config.value.public_upstream
        }
      }
    }
  }

  dynamic "virtual_repository_config" {
    for_each = each.value.mode == "VIRTUAL_REPOSITORY" ? [1] : []
    content {
      dynamic "upstream_policies" {
        for_each = local.resolved_upstreams[each.key]
        content {
          id         = upstream_policies.value.id
          repository = upstream_policies.value.repository
          priority   = upstream_policies.value.priority
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = each.value.mode != "REMOTE_REPOSITORY" || each.value.remote != null
      error_message = "mode = REMOTE_REPOSITORY requires the remote object ({ public_upstream })."
    }
    precondition {
      condition     = each.value.mode != "REMOTE_REPOSITORY" || contains(["DOCKER", "MAVEN", "NPM", "PYTHON"], each.value.format)
      error_message = "Remote (proxy) repositories support DOCKER, MAVEN, NPM and PYTHON formats in this module."
    }
    precondition {
      condition     = each.value.mode != "VIRTUAL_REPOSITORY" || length(each.value.virtual_upstreams) > 0
      error_message = "mode = VIRTUAL_REPOSITORY requires at least one entry in virtual_upstreams."
    }
    precondition {
      condition = alltrue([
        for p in each.value.cleanup_policies : (p.condition == null) != (p.most_recent_versions == null)
      ])
      error_message = "Each cleanup policy must set exactly one of condition or most_recent_versions."
    }
  }
}

# Least-privilege per-repository IAM (additive members, not authoritative).
resource "google_artifact_registry_repository_iam_member" "reader" {
  for_each = local.reader_bindings

  project    = var.project_id
  location   = var.location
  repository = google_artifact_registry_repository.this[each.value.repo_key].repository_id
  role       = "roles/artifactregistry.reader"
  member     = each.value.member
}

resource "google_artifact_registry_repository_iam_member" "writer" {
  for_each = local.writer_bindings

  project    = var.project_id
  location   = var.location
  repository = google_artifact_registry_repository.this[each.value.repo_key].repository_id
  role       = "roles/artifactregistry.writer"
  member     = each.value.member
}
