output "cluster_name" {
  value = google_container_cluster.this.name
}

output "location" {
  value = google_container_cluster.this.location
}

output "dns_endpoint" {
  value = google_container_cluster.this.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint
}

output "get_credentials_command" {
  value = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --region ${var.region} --project ${var.project_id} --dns-endpoint"
}

output "network" {
  value = google_compute_network.vpc.name
}

output "dns_domain" {
  value = var.dns_domain
}

output "external_dns_gsa" {
  value = google_service_account.external_dns.email
}

output "external_secrets_gsa" {
  value = google_service_account.external_secrets.email
}

output "manual_secrets" {
  description = "Secrets you must fill with: gcloud secrets versions add <id> --data-file=-"
  value       = [for s in local.manual_secrets : google_secret_manager_secret.platform[s].secret_id]
}

output "bastion_socks_command" {
  value = var.enable_bastion ? "gcloud compute ssh ${google_compute_instance.bastion[0].name} --zone ${google_compute_instance.bastion[0].zone} --project ${var.project_id} --tunnel-through-iap -- -N -D 1080" : null
}
