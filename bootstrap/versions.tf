terraform {
  required_version = ">= 1.11.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }

  # Run once with local state, then uncomment and `terraform init -migrate-state`
  # backend "gcs" {
  #   bucket = "<project_id>-tfstate"
  #   prefix = "bootstrap"
  # }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
