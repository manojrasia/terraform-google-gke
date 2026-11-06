# ---------- Node service account (least privilege) ----------
resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${var.cluster_name}-nodes"
  display_name = "GKE nodes - ${var.cluster_name}"
}

resource "google_project_iam_member" "nodes" {
  for_each = toset([
    "roles/container.defaultNodeServiceAccount",
    "roles/artifactregistry.reader",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# ---------- Human access (via IAM, works over the DNS endpoint) ----------
resource "google_project_iam_member" "cluster_admins" {
  for_each = toset(var.cluster_admins)
  project  = var.project_id
  role     = "roles/container.admin"
  member   = each.value
}

resource "google_project_iam_member" "cluster_developers" {
  for_each = toset(var.cluster_developers)
  project  = var.project_id
  role     = "roles/container.developer"
  member   = each.value
}
