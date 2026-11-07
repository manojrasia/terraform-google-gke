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
  value = local.domain
}

output "ingress_exposure" {
  value = var.ingress_exposure
}

output "ingress_public_ip" {
  value = google_compute_address.ingress_public.address
}

output "nat_ip" {
  value = google_compute_address.nat.address
}

output "dns_name_servers" {
  description = "Only for a public_domain: add these as NS records for the domain at your registrar"
  value       = local.public && local.dns_zone_enabled ? google_dns_managed_zone.this[0].name_servers : null
}

output "urls" {
  value = { for h in ["argocd", "grafana", "prometheus", "alertmanager", "gpm", "dex"] : h => "http://${h}.${local.domain}" }
}

output "github_oauth_app" {
  description = "Values for the GitHub OAuth App (they change only if the domain changes)"
  value = {
    homepage_url = "http://argocd.${local.domain}"
    callback_url = "http://dex.${local.domain}/dex/callback"
  }
}

# Handed to Argo CD by scripts/bootstrap-argocd.sh as values of the root app.
# This is how the Terraform switch reaches the cluster: no second place to edit.
output "platform_values" {
  value = {
    cluster = {
      domain = local.domain
    }
    ingress = {
      exposure     = var.ingress_exposure
      publicIP     = google_compute_address.ingress_public.address
      sourceRanges = local.public_source_ranges
    }
    dns = {
      managed    = local.dns_zone_enabled
      visibility = local.public ? "public" : "private"
    }
  }
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
  value = var.enable_bastion && !local.public ? "gcloud compute ssh ${google_compute_instance.bastion[0].name} --zone ${google_compute_instance.bastion[0].zone} --project ${var.project_id} --tunnel-through-iap -- -N -D 1080" : null
}
