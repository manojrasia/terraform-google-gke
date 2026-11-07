locals {
  node_tag    = "${var.cluster_name}-node"
  bastion_tag = "${var.cluster_name}-bastion"
  labels      = merge(var.labels, { cluster = var.cluster_name, environment = var.environment, managed-by = "terraform" })

  public = var.ingress_exposure == "public"

  # Hostname suffix used by every route: <app>.<domain>
  sslip_domain = "${replace(google_compute_address.ingress_public.address, ".", "-")}.sslip.io"
  domain       = local.public ? (var.public_domain != "" ? var.public_domain : local.sslip_domain) : var.dns_domain

  # A Cloud DNS zone (and ExternalDNS) is only needed when we own the domain
  dns_zone_enabled = !local.public || var.public_domain != ""

  # Pods reach public URLs (e.g. Dex) through Cloud NAT, so its IP must always be allowed
  public_source_ranges = distinct(concat(var.public_ingress_allowed_cidrs, ["${google_compute_address.nat.address}/32"]))
}
