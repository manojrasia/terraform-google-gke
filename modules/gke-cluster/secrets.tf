# Platform secrets live in Secret Manager; External Secrets syncs them into the cluster.
# Generated secrets use write-only arguments: the values are NEVER stored in Terraform state.
# Manual secrets are created empty - add the value with `gcloud secrets versions add`.

locals {
  generated_secrets = [
    "dex-argocd-client-secret",
    "dex-oauth2-proxy-client-secret",
    "dex-grafana-client-secret",
    "oauth2-proxy-cookie-secret", # 32 chars = valid AES key for oauth2-proxy
    "grafana-admin-password",
  ]

  manual_secrets = concat(
    ["dex-github-client-secret"],
    var.enable_slack_alerts ? ["alertmanager-slack-webhook"] : [],
    var.enable_wiz ? ["wiz-client-id", "wiz-client-token"] : [],
  )
}

resource "google_secret_manager_secret" "platform" {
  for_each  = toset(concat(local.generated_secrets, local.manual_secrets))
  project   = var.project_id
  secret_id = "${var.cluster_name}-${each.value}"
  labels    = local.labels

  replication {
    auto {}
  }
}

ephemeral "random_password" "generated" {
  for_each = toset(local.generated_secrets)
  length   = 32
  special  = false
}

resource "google_secret_manager_secret_version" "generated" {
  for_each = toset(local.generated_secrets)
  secret   = google_secret_manager_secret.platform[each.value].id

  secret_data_wo         = ephemeral.random_password.generated[each.value].result
  secret_data_wo_version = 1 # bump to rotate
}
