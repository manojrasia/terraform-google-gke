terraform {
  required_version = ">= 1.11.0"

  backend "gcs" {} # configured with: terraform init -backend-config=backend.hcl

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

provider "google" {
  project = local.project_id
  region  = local.region

  default_labels = {
    managed-by  = "terraform"
    environment = "dev"
  }
}
