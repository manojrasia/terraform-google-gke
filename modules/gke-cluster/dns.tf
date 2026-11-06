# Private zone: hostnames resolve only inside this VPC. ExternalDNS writes the records.
resource "google_dns_managed_zone" "internal" {
  project       = var.project_id
  name          = replace(var.dns_domain, ".", "-")
  dns_name      = "${var.dns_domain}."
  description   = "Internal hostnames for ${var.cluster_name} (managed by ExternalDNS)"
  visibility    = "private"
  force_destroy = true
  labels        = local.labels

  private_visibility_config {
    networks {
      network_url = google_compute_network.vpc.id
    }
  }
}
