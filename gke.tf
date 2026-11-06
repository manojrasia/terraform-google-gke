resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  project  = var.project_id
  location = var.region # regional = HA control plane across 3 zones

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.subnet.id

  # Manage nodes via a separate node pool resource
  remove_default_node_pool = true
  initial_node_count       = 1

  deletion_protection = var.deletion_protection
  networking_mode     = "VPC_NATIVE"
  datapath_provider   = "ADVANCED_DATAPATH" # Dataplane V2 (eBPF, built-in network policy)

  release_channel {
    channel = var.release_channel
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # ---- Internal / private cluster ----
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr

    master_global_access_config {
      enabled = true
    }
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = var.subnet_cidr
      display_name = "gke-subnet"
    }

    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  # ---- Workload Identity ----
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  enable_shielded_nodes = true

  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }

  maintenance_policy {
    recurring_window {
      # Weekends 18:30-23:30 UTC (00:00-05:00 IST)
      start_time = "2025-01-04T18:30:00Z"
      end_time   = "2025-01-04T23:30:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
    }
  }

  resource_labels = var.labels

  # Temporary default pool also uses the dedicated SA (works even if default compute SA is disabled)
  node_config {
    service_account = google_service_account.gke_nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  lifecycle {
    ignore_changes = [node_config, initial_node_count]
  }

  depends_on = [
    google_project_service.services,
    google_project_iam_member.gke_nodes_roles,
    google_compute_router_nat.nat,
  ]
}

resource "google_container_node_pool" "primary" {
  name     = "${var.cluster_name}-pool"
  project  = var.project_id
  location = var.region
  cluster  = google_container_cluster.primary.name

  node_locations     = var.zones
  initial_node_count = var.initial_nodes_per_zone

  autoscaling {
    min_node_count = var.min_nodes_per_zone
    max_node_count = var.max_nodes_per_zone
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type    = var.machine_type
    disk_size_gb    = var.disk_size_gb
    disk_type       = var.disk_type
    image_type      = "COS_CONTAINERD"
    spot            = var.use_spot
    service_account = google_service_account.gke_nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    # Required for Workload Identity on nodes
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }

    labels = var.labels
    tags   = ["gke-node", var.cluster_name]
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }
}
