variable "project_id" {
  description = "GCP project ID that hosts the repositories."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project ID (6-30 chars, lowercase letters, digits, hyphens)."
  }
}

variable "location" {
  description = "Region (e.g. us-central1) or multi-region (us, europe, asia) for all repositories in this module."
  type        = string
}

variable "repositories" {
  description = "Repositories keyed by repository_id. mode selects STANDARD_REPOSITORY (default), REMOTE_REPOSITORY (set remote.public_upstream) or VIRTUAL_REPOSITORY (set virtual_upstreams; sibling repos may be referenced by key). reader_members / writer_members get roles/artifactregistry.reader|writer on the repo."
  type = map(object({
    format                 = string
    mode                   = optional(string, "STANDARD_REPOSITORY")
    description            = optional(string, "Managed by Terraform (IaC Bazaar gcp-artifact-registry).")
    kms_key_name           = optional(string)
    labels                 = optional(map(string), {})
    docker_immutable_tags  = optional(bool, true)
    cleanup_policy_dry_run = optional(bool, false)
    cleanup_policies = optional(map(object({
      action = string
      condition = optional(object({
        tag_state             = optional(string)
        tag_prefixes          = optional(list(string))
        package_name_prefixes = optional(list(string))
        older_than            = optional(string)
        newer_than            = optional(string)
      }))
      most_recent_versions = optional(object({
        package_name_prefixes = optional(list(string))
        keep_count            = optional(number)
      }))
    })), {})
    remote = optional(object({
      description     = optional(string, "Pull-through proxy of a public upstream repository.")
      public_upstream = string
    }))
    virtual_upstreams = optional(list(object({
      id         = string
      repository = string
      priority   = optional(number, 1)
    })), [])
    reader_members = optional(list(string), [])
    writer_members = optional(list(string), [])
  }))

  validation {
    condition = alltrue([
      for repo_key in keys(var.repositories) : can(regex("^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", repo_key))
    ])
    error_message = "Each map key is the repository_id: 1-63 chars, lowercase letters, digits and hyphens, starting with a letter."
  }

  validation {
    condition = alltrue([
      for r in var.repositories : contains(["DOCKER", "MAVEN", "NPM", "PYTHON", "APT", "YUM", "GO", "GENERIC"], r.format)
    ])
    error_message = "format must be one of DOCKER, MAVEN, NPM, PYTHON, APT, YUM, GO, GENERIC."
  }

  validation {
    condition = alltrue([
      for r in var.repositories : contains(["STANDARD_REPOSITORY", "REMOTE_REPOSITORY", "VIRTUAL_REPOSITORY"], r.mode)
    ])
    error_message = "mode must be STANDARD_REPOSITORY, REMOTE_REPOSITORY or VIRTUAL_REPOSITORY."
  }

  validation {
    condition = alltrue(flatten([
      for r in var.repositories : [
        for p in values(r.cleanup_policies) : contains(["DELETE", "KEEP"], p.action)
      ]
    ]))
    error_message = "Cleanup policy action must be DELETE or KEEP."
  }

  validation {
    condition = alltrue([
      for r in var.repositories : r.remote == null ? true : contains(["DOCKER_HUB", "MAVEN_CENTRAL", "NPMJS", "PYPI"], r.remote.public_upstream)
    ])
    error_message = "remote.public_upstream must be one of DOCKER_HUB, MAVEN_CENTRAL, NPMJS, PYPI."
  }

  validation {
    condition = alltrue(flatten([
      for r in var.repositories : [
        for member in concat(r.reader_members, r.writer_members) : !contains(["allUsers", "allAuthenticatedUsers"], member)
      ]
    ]))
    error_message = "Public members (allUsers, allAuthenticatedUsers) are not allowed on registries; grant explicit identities."
  }
}

variable "labels" {
  description = "Labels merged into every repository's labels."
  type        = map(string)
  default     = {}
}
