resource "google_container_cluster" "this" {
  name     = var.cluster_name
  project  = var.project_id
  location = var.region # regional control plane (3 zones)

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.nodes.id

  # No default node pool (GKE >= 1.36.4-gke.1469000): node pools are managed below.
  deletion_protection = var.deletion_protection
  networking_mode     = "VPC_NATIVE"
  datapath_provider   = "ADVANCED_DATAPATH" # Dataplane V2 (eBPF, NetworkPolicy built in)

  release_channel {
    channel = var.release_channel
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true # no public IP endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr

    master_global_access_config {
      enabled = true
    }
  }

  control_plane_endpoints_config {
    # IAM-authenticated DNS endpoint: CI and admins reach the API without a bastion/VPN.
    # Every request still needs container.* IAM permissions.
    dns_endpoint_config {
      allow_external_traffic = var.enable_dns_endpoint
    }
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = var.subnet_cidr
      display_name = "nodes-subnet"
    }

    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  enable_shielded_nodes = true

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

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
    dns_cache_config {
      enabled = true # NodeLocal DNSCache
    }
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = false # the platform runs its own Prometheus
    }
  }

  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_start_time
      end_time   = timeadd(var.maintenance_start_time, "5h")
      recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
    }
  }

  cost_management_config {
    enabled = true
  }

  resource_labels = local.labels

  depends_on = [
    google_project_iam_member.nodes,
    google_compute_router_nat.nat,
  ]
}

resource "google_container_node_pool" "pools" {
  for_each = var.node_pools

  name           = each.key
  project        = var.project_id
  location       = var.region
  cluster        = google_container_cluster.this.name
  node_locations = var.zones

  initial_node_count = each.value.min_nodes

  autoscaling {
    min_node_count  = each.value.min_nodes
    max_node_count  = each.value.max_nodes
    location_policy = "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type    = each.value.machine_type
    disk_size_gb    = each.value.disk_size_gb
    disk_type       = each.value.disk_type
    image_type      = "COS_CONTAINERD"
    spot            = each.value.spot
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    tags            = [local.node_tag]
    labels          = merge({ pool = each.key }, each.value.labels)
    resource_labels = local.labels

    workload_metadata_config {
      mode = "GKE_METADATA" # Workload Identity
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }
}
