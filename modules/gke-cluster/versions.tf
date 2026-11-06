terraform {
  required_version = ">= 1.11.0" # write-only arguments

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 8.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7" # ephemeral random_password
    }
  }
}
