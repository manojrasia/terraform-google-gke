# Cluster "dev-gke". To add a cluster: copy this folder (e.g. live/prod),
# change the locals and module inputs, backend.hcl prefix, and add a
# matching platform/clusters/<cluster_name>.yaml.

locals {
  project_id = "boreal-conquest-421512"
  region     = "asia-south1"
}

module "cluster" {
  source = "../../modules/gke-cluster"

  project_id   = local.project_id
  region       = local.region
  cluster_name = "dev-gke"
  environment  = "dev"
  dns_domain   = "dev.stack.internal"

  # Must not overlap with other clusters you may peer/VPN together
  subnet_cidr      = "10.10.0.0/20"
  pods_cidr        = "10.20.0.0/16"
  services_cidr    = "10.30.0.0/20"
  master_ipv4_cidr = "172.16.0.0/28"

  node_pools = {
    general = {
      machine_type = "e2-standard-4"
      min_nodes    = 1 # per zone -> 3 nodes minimum
      max_nodes    = 2
      disk_size_gb = 50
      disk_type    = "pd-standard" # dev: keeps SSD quota free
    }
  }

  cluster_admins     = ["user:manoj1chaurasia2@gmail.com"]
  cluster_developers = []

  deletion_protection = true
  enable_bastion      = true
  enable_wiz          = false
  enable_slack_alerts = false
}
