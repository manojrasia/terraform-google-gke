output "cluster" {
  value = {
    name                    = module.cluster.cluster_name
    location                = module.cluster.location
    dns_endpoint            = module.cluster.dns_endpoint
    get_credentials_command = module.cluster.get_credentials_command
    dns_domain              = module.cluster.dns_domain
    bastion_socks_command   = module.cluster.bastion_socks_command
  }
}

output "manual_secrets" {
  value = module.cluster.manual_secrets
}
