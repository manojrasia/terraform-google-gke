# ---------- Identity ----------
variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "cluster_name" {
  description = "Short name; used as prefix for every resource (max 20 chars)"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,19}$", var.cluster_name))
    error_message = "cluster_name: lowercase letters, digits, hyphens; 2-20 chars."
  }
}

variable "environment" {
  type = string
}

variable "labels" {
  type    = map(string)
  default = {}
}

# ---------- Network ----------
variable "subnet_cidr" {
  type = string
}

variable "pods_cidr" {
  type = string
}

variable "services_cidr" {
  type = string
}

variable "master_ipv4_cidr" {
  description = "/28 for the control plane; must be unique per VPC"
  type        = string
}

variable "master_authorized_networks" {
  description = "Extra CIDRs (VPN, on-prem) allowed to the private IP endpoint. The subnet is always allowed."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

# ---------- Cluster ----------
variable "release_channel" {
  type    = string
  default = "REGULAR"
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "enable_dns_endpoint" {
  description = "IAM-protected DNS endpoint for the control plane, used by CI (GitHub Actions) - no bastion needed"
  type        = bool
  default     = true
}

variable "zones" {
  description = "Node zones; null = all zones in the region"
  type        = list(string)
  default     = null
}

variable "node_pools" {
  description = "Node pools keyed by short name. Node counts are PER ZONE."
  type = map(object({
    machine_type = string
    min_nodes    = number
    max_nodes    = number
    disk_size_gb = optional(number, 50)
    disk_type    = optional(string, "pd-balanced")
    spot         = optional(bool, false)
    labels       = optional(map(string), {})
  }))
}

variable "maintenance_start_time" {
  description = "RFC3339 start of the weekly maintenance window (default = Sat 00:00 IST)"
  type        = string
  default     = "2025-01-04T18:30:00Z"
}

# ---------- Access ----------
variable "cluster_admins" {
  description = "IAM members with full cluster access (e.g. user:alice@example.com)"
  type        = list(string)
  default     = []
}

variable "cluster_developers" {
  description = "IAM members with namespace-level read/write (roles/container.developer)"
  type        = list(string)
  default     = []
}

variable "enable_bastion" {
  description = "Small IAP-only VM for browsing internal UIs (SOCKS proxy)"
  type        = bool
  default     = true
}

# ---------- Platform ----------
variable "dns_domain" {
  description = "Private DNS zone for internal hostnames, e.g. dev.stack.internal"
  type        = string
}

variable "enable_wiz" {
  type    = bool
  default = false
}

variable "enable_slack_alerts" {
  type    = bool
  default = false
}

# ---------- Exposure (one switch) ----------
variable "ingress_exposure" {
  description = <<-EOT
    How the platform UIs and workloads are reached:
      internal = internal LB + private DNS zone; reach it through the bastion (SOCKS proxy)
      public   = public LB with a static IP; open the URLs straight from your laptop
    Changing it is safe at any time: both IPs stay reserved, Argo CD switches the gateway.
  EOT
  type        = string
  default     = "internal"
  validation {
    condition     = contains(["internal", "public"], var.ingress_exposure)
    error_message = "ingress_exposure must be \"internal\" or \"public\"."
  }
}

variable "public_domain" {
  description = <<-EOT
    Only for ingress_exposure = "public". Empty = no DNS needed: hostnames use sslip.io
    (e.g. argocd.34-93-10-20.sslip.io resolves to 34.93.10.20). Set a domain you own
    (e.g. dev.example.com) to get a public Cloud DNS zone managed by ExternalDNS instead.
  EOT
  type        = string
  default     = ""
}

variable "public_ingress_allowed_cidrs" {
  description = "Only for ingress_exposure = \"public\": client CIDRs allowed to reach the public LB. The cluster's NAT IP is always added."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "public_control_plane" {
  description = <<-EOT
    true = control plane also gets a public IP endpoint (restricted to master_authorized_networks).
    Usually not needed: the IAM-protected DNS endpoint already lets kubectl work from anywhere.
  EOT
  type        = bool
  default     = false
}
