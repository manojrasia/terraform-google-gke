resource "google_compute_network" "vpc" {
  name                    = "${var.cluster_name}-vpc"
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "nodes" {
  name                     = "${var.cluster_name}-${var.region}"
  project                  = var.project_id
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# ---------- Static IPs ----------
# Fixed egress IP: allow-listed on the public LB, and handy for allow-lists elsewhere.
resource "google_compute_address" "nat" {
  name    = "${var.cluster_name}-nat"
  project = var.project_id
  region  = var.region
  labels  = local.labels
}

# Public gateway IP. Always reserved, so switching ingress_exposure back and forth never
# tries to delete an IP that a load balancer is still using, and the URLs never change.
resource "google_compute_address" "ingress_public" {
  name         = "${var.cluster_name}-ingress"
  project      = var.project_id
  region       = var.region
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"
  labels       = local.labels
}

# Egress for private nodes (image pulls, GitHub, Wiz)
resource "google_compute_router" "router" {
  name    = "${var.cluster_name}-router"
  project = var.project_id
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.cluster_name}-nat"
  project                            = var.project_id
  region                             = var.region
  router                             = google_compute_router.router.name
  nat_ip_allocate_option             = "MANUAL_ONLY"
  nat_ips                            = [google_compute_address.nat.self_link]
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Private clusters only allow control plane -> nodes on 443/10250.
# Admission webhooks on other ports: Gatekeeper 8443, Envoy Gateway & pvc-autoresizer 9443.
resource "google_compute_firewall" "master_to_webhooks" {
  name          = "${var.cluster_name}-allow-master-webhooks"
  project       = var.project_id
  network       = google_compute_network.vpc.name
  direction     = "INGRESS"
  source_ranges = [var.master_ipv4_cidr]
  target_tags   = [local.node_tag]

  allow {
    protocol = "tcp"
    ports    = ["8443", "9443"]
  }
}

resource "google_compute_firewall" "iap_ssh_bastion" {
  count = var.enable_bastion ? 1 : 0

  name          = "${var.cluster_name}-allow-iap-ssh"
  project       = var.project_id
  network       = google_compute_network.vpc.name
  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"] # Google IAP
  target_tags   = [local.bastion_tag]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
