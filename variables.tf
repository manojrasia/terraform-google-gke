# ---------- Project ----------
variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "asia-south1"
}

variable "zones" {
  description = "Zones for the node pool (regional cluster spreads nodes across these)"
  type        = list(string)
  default     = ["asia-south1-a", "asia-south1-b", "asia-south1-c"]
}

# ---------- Network ----------
variable "network_name" {
  type    = string
  default = "gke-vpc"
}

variable "subnet_name" {
  type    = string
  default = "gke-subnet-asia-south1"
}

variable "subnet_cidr" {
  description = "Primary range for nodes (and bastion)"
  type        = string
  default     = "10.10.0.0/20"
}

variable "pods_range_name" {
  type    = string
  default = "gke-pods"
}

variable "pods_cidr" {
  description = "Secondary range for pods"
  type        = string
  default     = "10.20.0.0/16"
}

variable "services_range_name" {
  type    = string
  default = "gke-services"
}

variable "services_cidr" {
  description = "Secondary range for services"
  type        = string
  default     = "10.30.0.0/20"
}

variable "master_ipv4_cidr" {
  description = "/28 range for the GKE control plane (must not overlap any other range)"
  type        = string
  default     = "172.16.0.0/28"
}

# ---------- Cluster ----------
variable "cluster_name" {
  type    = string
  default = "private-gke-cluster"
}

variable "release_channel" {
  description = "RAPID, REGULAR or STABLE"
  type        = string
  default     = "REGULAR"
}

variable "enable_private_endpoint" {
  description = "true = control plane reachable ONLY via internal IP (fully internal cluster)"
  type        = bool
  default     = true
}

variable "master_authorized_networks" {
  description = "Extra CIDRs allowed to reach the control plane (the subnet is always added)"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "deletion_protection" {
  description = "Prevents accidental terraform destroy of the cluster"
  type        = bool
  default     = true
}

# ---------- Node pool ----------
variable "machine_type" {
  type    = string
  default = "e2-standard-4"
}

variable "disk_size_gb" {
  type    = number
  default = 100
}

variable "disk_type" {
  type    = string
  default = "pd-balanced"
}

variable "min_nodes_per_zone" {
  type    = number
  default = 1
}

variable "max_nodes_per_zone" {
  type    = number
  default = 3
}

variable "initial_nodes_per_zone" {
  type    = number
  default = 1
}

variable "use_spot" {
  description = "Use Spot VMs for the node pool (cheaper, preemptible; good for dev)"
  type        = bool
  default     = false
}

# ---------- Bastion ----------
variable "create_bastion" {
  description = "Create an internal-only bastion VM (SSH via IAP) to run kubectl"
  type        = bool
  default     = true
}

variable "bastion_zone" {
  type    = string
  default = "asia-south1-a"
}

# ---------- Workload Identity examples ----------
variable "workload_identity_bindings" {
  description = <<-EOT
    Optional: Google service accounts to create and bind to Kubernetes service accounts.
    key = GSA account_id. Example:
    {
      "app-gsa" = {
        namespace = "default"
        ksa_name  = "app-ksa"
        roles     = ["roles/storage.objectViewer"]
      }
    }
  EOT
  type = map(object({
    namespace = string
    ksa_name  = string
    roles     = list(string)
  }))
  default = {}
}

variable "labels" {
  type = map(string)
  default = {
    env        = "dev"
    managed-by = "terraform"
  }
}
