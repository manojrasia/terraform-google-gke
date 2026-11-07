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

  # ------------------------------------------------------------------
  # HOW YOU REACH THE UIs - the only switch you need
  #   "public"   -> open http://argocd.<ip>.sslip.io from your laptop, no tunnel, no hosts file
  #   "internal" -> internal LB + private DNS; browse through the bastion SOCKS proxy
  # Commit + merge; CI applies Terraform and re-points Argo CD. Both modes can be toggled any time.
  # ------------------------------------------------------------------
  ingress_exposure = "public"

  # Used when ingress_exposure = "internal"
  dns_domain = "dev.stack.internal"

  # Used when ingress_exposure = "public"
  public_domain                = ""            # "" = automatic <ip>.sslip.io, or a domain you own
  public_ingress_allowed_cidrs = ["0.0.0.0/0"] # tighten to your IP: ["<curl ifconfig.me>/32"]

  # Control plane: kubectl already works from anywhere through the IAM-protected DNS endpoint.
  # Set true only if you also want the classic public IP endpoint; then add your IP below.
  public_control_plane       = false
  master_authorized_networks = [] # e.g. [{ cidr_block = "1.2.3.4/32", display_name = "me" }]

  # Must not overlap with other clusters you may peer/VPN together
  subnet_cidr      = "10.10.0.0/20"
  pods_cidr        = "10.20.0.0/16"
  services_cidr    = "10.30.0.0/20"
  master_ipv4_cidr = "172.16.0.0/28"

  node_pools = {
    general = {
      machine_type = "e2-standard-2" # 2 vCPU / 8 GB
      min_nodes    = 1               # per zone -> 3 nodes = 6 vCPU
      max_nodes    = 2               # up to 12 vCPU
      disk_size_gb = 50
      disk_type    = "pd-standard"
    }
  }

  cluster_admins     = ["user:manoj1chaurasia2@gmail.com"]
  cluster_developers = []

  deletion_protection = false # dev: lets `terraform destroy` work in one go
  enable_bastion      = true  # only needed for "internal"; harmless otherwise
  enable_wiz          = false
  enable_slack_alerts = false
}
