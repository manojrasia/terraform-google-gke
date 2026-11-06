output "cluster_name" {
  value = google_container_cluster.primary.name
}

output "cluster_location" {
  value = google_container_cluster.primary.location
}

output "cluster_private_endpoint" {
  value = google_container_cluster.primary.private_cluster_config[0].private_endpoint
}

output "workload_identity_pool" {
  value = google_container_cluster.primary.workload_identity_config[0].workload_pool
}

output "network" {
  value = google_compute_network.vpc.name
}

output "subnet" {
  value = google_compute_subnetwork.subnet.name
}

output "node_service_account" {
  value = google_service_account.gke_nodes.email
}

output "bastion_ssh_command" {
  value = var.create_bastion ? "gcloud compute ssh ${google_compute_instance.bastion[0].name} --zone ${var.bastion_zone} --project ${var.project_id} --tunnel-through-iap" : null
}

output "get_credentials_command" {
  value = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${var.region} --project ${var.project_id} --internal-ip"
}

output "workload_identity_gsas" {
  value = { for k, v in google_service_account.wi : k => v.email }
}
