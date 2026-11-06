locals {
  node_tag    = "${var.cluster_name}-node"
  bastion_tag = "${var.cluster_name}-bastion"
  labels      = merge(var.labels, { cluster = var.cluster_name, environment = var.environment, managed-by = "terraform" })
}
