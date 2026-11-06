# Extra infra needed by k8s-stack on the private GKE cluster.
# Drop this file into your terraform/ folder next to gke.tf and run terraform apply.

variable "dns_domain" {
  description = "Private DNS domain for the stack's hostnames (grafana.<domain>, argocd.<domain>, ...)"
  type        = string
  default     = "stack.internal"
}

resource "google_project_service" "dns" {
  project            = var.project_id
  service            = "dns.googleapis.com"
  disable_on_destroy = false
}

# ---- Private Cloud DNS zone, visible only inside gke-vpc ----
resource "google_dns_managed_zone" "stack" {
  project       = var.project_id
  name          = replace(var.dns_domain, ".", "-")
  dns_name      = "${var.dns_domain}."
  description   = "Internal hostnames for the k8s stack (managed by ExternalDNS)"
  visibility    = "private"
  force_destroy = true # lets terraform destroy remove records ExternalDNS created

  private_visibility_config {
    networks {
      network_url = google_compute_network.vpc.id
    }
  }

  depends_on = [google_project_service.dns]
}

# ---- ExternalDNS identity via Workload Identity (no JSON keys) ----
resource "google_service_account" "external_dns" {
  project      = var.project_id
  account_id   = "external-dns"
  display_name = "ExternalDNS for ${var.cluster_name}"
}

resource "google_project_iam_member" "external_dns_dns_admin" {
  project = var.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.external_dns.email}"
}

# KSA external-dns/external-dns may act as the GSA above
resource "google_service_account_iam_member" "external_dns_wi" {
  service_account_id = google_service_account.external_dns.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[external-dns/external-dns]"

  depends_on = [google_container_cluster.primary]
}

# ---- Private-cluster webhook firewall ----
# GKE only lets the control plane reach nodes on 443/10250. Admission webhooks
# on other ports time out ("context deadline exceeded") without this rule:
#   8443 = Gatekeeper, 9443 = Envoy Gateway topology injector + pvc-autoresizer
resource "google_compute_firewall" "master_to_webhooks" {
  name      = "${var.network_name}-allow-master-webhooks"
  project   = var.project_id
  network   = google_compute_network.vpc.name
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["8443", "9443"]
  }

  source_ranges = [var.master_ipv4_cidr]
  target_tags   = ["gke-node"]
}

output "stack_dns_zone" {
  value = google_dns_managed_zone.stack.name
}

output "external_dns_gsa" {
  value = google_service_account.external_dns.email
}
