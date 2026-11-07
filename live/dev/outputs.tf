output "cluster" {
  value = {
    name                    = module.cluster.cluster_name
    location                = module.cluster.location
    dns_endpoint            = module.cluster.dns_endpoint
    get_credentials_command = module.cluster.get_credentials_command
    dns_domain              = module.cluster.dns_domain
    ingress_exposure        = module.cluster.ingress_exposure
    ingress_public_ip       = module.cluster.ingress_public_ip
    nat_ip                  = module.cluster.nat_ip
    bastion_socks_command   = module.cluster.bastion_socks_command
    dns_name_servers        = module.cluster.dns_name_servers
  }
}

output "urls" {
  value = module.cluster.urls
}

output "github_oauth_app" {
  value = module.cluster.github_oauth_app
}

# Read by scripts/bootstrap-argocd.sh - do not rename
output "platform_values" {
  value = module.cluster.platform_values
}

output "manual_secrets" {
  value = module.cluster.manual_secrets
}
