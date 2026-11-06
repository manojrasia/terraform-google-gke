# Internal-only VM (no public IP) used to run kubectl against the private endpoint.
# Connect with: gcloud compute ssh <name> --zone <zone> --tunnel-through-iap

resource "google_service_account" "bastion" {
  count = var.create_bastion ? 1 : 0

  project      = var.project_id
  account_id   = "${var.cluster_name}-bastion"
  display_name = "Bastion SA for ${var.cluster_name}"
}

resource "google_project_iam_member" "bastion_roles" {
  for_each = var.create_bastion ? toset([
    "roles/container.developer",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ]) : toset([])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.bastion[0].email}"
}

resource "google_compute_instance" "bastion" {
  count = var.create_bastion ? 1 : 0

  name         = "${var.cluster_name}-bastion"
  project      = var.project_id
  zone         = var.bastion_zone
  machine_type = "e2-small"
  tags         = ["bastion"]
  labels       = var.labels

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
    # no access_config block => no external IP
  }

  service_account {
    email  = google_service_account.bastion[0].email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot = true
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    apt-get update -y
    apt-get install -y kubectl google-cloud-cli-gke-gcloud-auth-plugin
  EOT

  depends_on = [google_compute_router_nat.nat]
}
