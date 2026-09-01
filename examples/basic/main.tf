terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.0, < 8.0"
    }
  }
}

provider "google" {
  project = "example-project-123456"
  region  = "us-central1"
}

module "registry" {
  source     = "../../"
  project_id = "example-project-123456"
  location   = "us-central1"

  repositories = {
    "app-images" = {
      format = "DOCKER"
      cleanup_policies = {
        keep-latest-10 = {
          action               = "KEEP"
          most_recent_versions = { keep_count = 10 }
        }
        delete-stale-untagged = {
          action    = "DELETE"
          condition = { tag_state = "UNTAGGED", older_than = "2592000s" }
        }
      }
      reader_members = ["serviceAccount:gke-nodes@example-project-123456.iam.gserviceaccount.com"]
      writer_members = ["serviceAccount:ci-builder@example-project-123456.iam.gserviceaccount.com"]
    }

    "dockerhub-proxy" = {
      format = "DOCKER"
      mode   = "REMOTE_REPOSITORY"
      remote = { public_upstream = "DOCKER_HUB" }
    }

    "all-images" = {
      format = "DOCKER"
      mode   = "VIRTUAL_REPOSITORY"
      virtual_upstreams = [
        { id = "internal", repository = "app-images", priority = 100 },
        { id = "dockerhub", repository = "dockerhub-proxy", priority = 1 },
      ]
    }
  }

  labels = {
    environment = "example"
    managed_by  = "iac-bazaar"
  }
}

output "repository_urls" {
  value = module.registry.repository_urls
}
