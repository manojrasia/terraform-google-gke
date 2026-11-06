# Optional: GSA <-> KSA bindings for Workload Identity.
# Populate var.workload_identity_bindings in terraform.tfvars.

resource "google_service_account" "wi" {
  for_each = var.workload_identity_bindings

  project      = var.project_id
  account_id   = each.key
  display_name = "WI GSA for ${each.value.namespace}/${each.value.ksa_name}"
}

# Let the Kubernetes SA impersonate the Google SA
resource "google_service_account_iam_member" "wi_user" {
  for_each = var.workload_identity_bindings

  service_account_id = google_service_account.wi[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${each.value.namespace}/${each.value.ksa_name}]"

  depends_on = [google_container_cluster.primary] # identity pool is created with the cluster
}

locals {
  wi_role_bindings = flatten([
    for gsa, cfg in var.workload_identity_bindings : [
      for role in cfg.roles : { gsa = gsa, role = role }
    ]
  ])
}

resource "google_project_iam_member" "wi_roles" {
  for_each = { for b in local.wi_role_bindings : "${b.gsa}-${b.role}" => b }

  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.wi[each.value.gsa].email}"
}
