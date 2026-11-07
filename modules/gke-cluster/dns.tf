# internal: private zone (resolves only inside this VPC)
# public + public_domain: public zone; delegate it from your registrar (see output dns_name_servers)
# public without public_domain: no zone at all, hostnames use sslip.io
resource "google_dns_managed_zone" "this" {
  count = local.dns_zone_enabled ? 1 : 0

  project       = var.project_id
  name          = "${var.cluster_name}-${local.public ? "public" : "private"}"
  dns_name      = "${local.domain}."
  description   = "Hostnames for ${var.cluster_name} (managed by ExternalDNS)"
  visibility    = local.public ? "public" : "private"
  force_destroy = true
  labels        = local.labels

  dynamic "private_visibility_config" {
    for_each = local.public ? [] : [1]
    content {
      networks {
        network_url = google_compute_network.vpc.id
      }
    }
  }
}

moved {
  from = google_dns_managed_zone.internal
  to   = google_dns_managed_zone.this[0]
}
