# Google service accounts used by in-cluster platform components through Workload Identity.

# ---------- ExternalDNS: may only change records in this cluster's zone ----------
resource "google_service_account" "external_dns" {
  project      = var.project_id
  account_id   = "${var.cluster_name}-edns"
  display_name = "ExternalDNS - ${var.cluster_name}"
}

resource "google_project_iam_member" "external_dns_reader" {
  project = var.project_id
  role    = "roles/dns.reader" # list zones
  member  = "serviceAccount:${google_service_account.external_dns.email}"
}

resource "google_dns_managed_zone_iam_member" "external_dns_zone_admin" {
  count        = local.dns_zone_enabled ? 1 : 0
  project      = var.project_id
  managed_zone = google_dns_managed_zone.this[0].name
  role         = "roles/dns.admin"
  member       = "serviceAccount:${google_service_account.external_dns.email}"
}

# ---------- External Secrets Operator: may only read this cluster's secrets ----------
resource "google_service_account" "external_secrets" {
  project      = var.project_id
  account_id   = "${var.cluster_name}-eso"
  display_name = "External Secrets - ${var.cluster_name}"
}

resource "google_secret_manager_secret_iam_member" "external_secrets" {
  for_each  = google_secret_manager_secret.platform
  project   = var.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.external_secrets.email}"
}

# ---------- Workload Identity bindings (KSA -> GSA) ----------
locals {
  wi_bindings = {
    external_dns     = { gsa = google_service_account.external_dns.name, ksa = "external-dns/external-dns" }
    external_secrets = { gsa = google_service_account.external_secrets.name, ksa = "external-secrets/external-secrets" }
  }
}

resource "google_service_account_iam_member" "workload_identity" {
  for_each           = local.wi_bindings
  service_account_id = each.value.gsa
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${each.value.ksa}]"

  depends_on = [google_container_cluster.this] # the identity pool is created with the cluster
}
