# Copy these into GitHub: Settings -> Secrets and variables -> Actions -> Variables
output "github_variables" {
  value = {
    GCP_PROJECT_ID   = var.project_id
    GCP_WIF_PROVIDER = google_iam_workload_identity_pool_provider.github.name
    GCP_TF_PLAN_SA   = google_service_account.plan.email
    GCP_TF_APPLY_SA  = google_service_account.apply.email
  }
}

output "state_bucket" {
  value = google_storage_bucket.tfstate.name
}
