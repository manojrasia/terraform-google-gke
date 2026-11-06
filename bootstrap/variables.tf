variable "project_id" {
  description = "GCP project that hosts the clusters"
  type        = string
}

variable "region" {
  description = "Default region (state bucket location)"
  type        = string
  default     = "asia-south1"
}

variable "github_repository" {
  description = "GitHub repo allowed to deploy, as owner/name"
  type        = string
}

variable "github_environments" {
  description = "GitHub Environments allowed to run terraform apply (one per cluster under live/)"
  type        = list(string)
  default     = ["dev"]
}
