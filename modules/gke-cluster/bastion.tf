# Optional IAP-only VM (no public IP). Used as a SOCKS proxy to open the internal UIs.
# It has NO Kubernetes permissions; people use their own identity for kubectl.

resource "google_service_account" "bastion" {
  count        = var.enable_bastion ? 1 : 0
  project      = var.project_id
  account_id   = "${var.cluster_name}-bastion"
  display_name = "Bastion - ${var.cluster_name}"
}

resource "google_project_iam_member" "bastion" {
  for_each = var.enable_bastion ? toset(["roles/logging.logWriter", "roles/monitoring.metricWriter"]) : toset([])
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.bastion[0].email}"
}

resource "google_compute_instance" "bastion" {
  count = var.enable_bastion ? 1 : 0

  name         = "${var.cluster_name}-bastion"
  project      = var.project_id
  zone         = "${var.region}-a"
  machine_type = "e2-micro"
  tags         = [local.bastion_tag]
  labels       = local.labels

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.nodes.id
  }

  service_account {
    email  = google_service_account.bastion[0].email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"
  }

  metadata_startup_script = "apt-get update -y && apt-get install -y kubectl google-cloud-cli-gke-gcloud-auth-plugin"

  depends_on = [google_compute_router_nat.nat]
}

# Who may SSH (via IAP + OS Login) to the bastion: admins and developers
locals {
  bastion_users = var.enable_bastion ? toset(concat(var.cluster_admins, var.cluster_developers)) : toset([])
}

resource "google_iap_tunnel_instance_iam_member" "bastion" {
  for_each = local.bastion_users
  project  = var.project_id
  zone     = google_compute_instance.bastion[0].zone
  instance = google_compute_instance.bastion[0].name
  role     = "roles/iap.tunnelResourceAccessor"
  member   = each.value
}

resource "google_compute_instance_iam_member" "bastion_oslogin" {
  for_each      = local.bastion_users
  project       = var.project_id
  zone          = google_compute_instance.bastion[0].zone
  instance_name = google_compute_instance.bastion[0].name
  role          = "roles/compute.osLogin"
  member        = each.value
}

# OS Login on a VM with a service account also requires actAs on that account
resource "google_service_account_iam_member" "bastion_act_as" {
  for_each           = local.bastion_users
  service_account_id = google_service_account.bastion[0].name
  role               = "roles/iam.serviceAccountUser"
  member             = each.value
}
