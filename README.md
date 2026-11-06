# GKE platform (private cluster + GitOps)

Private, regional GKE clusters in `asia-south1`, built with Terraform from GitHub
Actions (Workload Identity Federation, no keys), with every add-on managed by
Argo CD from this repo. Users log in with **GitHub** through Dex.

```
bootstrap/                one-time per project: APIs, state bucket, WIF, CI service accounts
modules/gke-cluster/      reusable cluster module (VPC, NAT, GKE, node pools, DNS, secrets, IAM)
live/<env>/               one folder per cluster (calls the module)
platform/
  clusters/<cluster>.yaml per-cluster inputs: domain, GitHub OAuth app, users
  apps/                   app-of-apps chart: one Argo CD Application per add-on
  values/                 shared Helm values per add-on
  charts/platform-config  gateway, routes, storage class, secret sync
  charts/policies         Gatekeeper policies
workloads/<app>/          team apps (kustomize base + overlays/<env>)
scripts/bootstrap-argocd.sh
.github/workflows/        terraform (plan on PR, apply on main) + platform validation
```

## How it fits together

1. **Terraform** (CI) creates the cluster, its private DNS zone, the Google
   service accounts for ExternalDNS / External Secrets, and the platform secrets
   in Secret Manager. Generated secrets use write-only arguments, so they are
   **never stored in Terraform state**.
2. The same CI job runs `scripts/bootstrap-argocd.sh` **once**: it installs Argo
   CD and creates the `root` Application. CI reaches the private control plane
   through GKE's **IAM-protected DNS endpoint** - no bastion or public IP.
3. Argo CD installs everything else from Git in order (sync waves):
   External Secrets + Envoy Gateway → gateway/routes/secret sync → ExternalDNS +
   Prometheus/Grafana → Dex, autoresizer, blackbox → oauth2-proxy, Argo CD
   itself, Gatekeeper → policies, Policy Manager, Wiz → your `workloads/`.
4. Every later change is a pull request. Argo CD reverts manual `kubectl` edits.

| Concern | How it's handled |
|---|---|
| CI credentials | WIF: PRs get a read-only SA; only jobs in a GitHub Environment can use the apply SA |
| Secrets | Secret Manager → External Secrets (Workload Identity). Nothing secret in Git or state |
| Login | Dex + GitHub. No local users; Argo CD admin disabled; Grafana login form disabled |
| Authorization | Only emails in `platform/clusters/<cluster>.yaml` get in (Argo CD RBAC, Grafana roles, oauth2-proxy allowlist) |
| Cluster access | IAM (`cluster_admins`/`cluster_developers` in `live/<env>/main.tf`) over the DNS endpoint |
| Network | Private nodes, no public endpoint, internal LB only, private DNS zone, Cloud NAT egress |
| Least privilege | Node SA minimal; ExternalDNS can edit only its zone; ESO can read only its cluster's secrets |
| HA | Regional control plane, nodes in 3 zones, 2+ replicas and PDBs for every add-on, Argo CD HA Redis |
| Policy | Gatekeeper: owner label, no privileged, requests/limits, no `latest` (start `dryrun`) |
| Upgrades | Chart versions pinned in `platform/apps/values.yaml`; Dependabot for actions + providers |

## First-time setup

### 1. Bootstrap the project (once, locally, as project Owner)

```bash
cd bootstrap
terraform init && terraform apply
terraform output github_variables
```

Optional but recommended: move this state into the new bucket - uncomment the
`backend "gcs"` block in `bootstrap/versions.tf`, then
`terraform init -migrate-state`.

### 2. Configure GitHub

- **Settings → Secrets and variables → Actions → Variables**: add
  `GCP_PROJECT_ID`, `GCP_WIF_PROVIDER`, `GCP_TF_PLAN_SA`, `GCP_TF_APPLY_SA`
  from the output above (they are identifiers, not secrets).
- **Settings → Environments**: create `dev` (for `prod`, add required reviewers).
- **Settings → Branches**: protect `main` (require PR + the `terraform` and
  `platform` checks).

### 3. Create the GitHub OAuth App (real users)

GitHub → **Settings → Developer settings → OAuth Apps → New OAuth App**:

| Field | Value |
|---|---|
| Homepage URL | `http://argocd.dev.stack.internal` |
| Authorization callback URL | `http://dex.dev.stack.internal/dex/callback` |

Put the **Client ID** in `platform/clusters/dev-gke.yaml` (`auth.github.clientID`)
and list your users' GitHub emails under `auth.admins` / `auth.viewers`.
If you use a GitHub organization, set `auth.github.orgs` so only its members can
authenticate at all.

> Emails must match the **primary verified email** on each user's GitHub account.

### 4. Deploy

Commit and push to `main`. The `terraform` workflow applies `live/dev` and
bootstraps Argo CD. Then store the GitHub client secret (Terraform created the
empty secret):

```bash
printf '%s' 'GITHUB_CLIENT_SECRET' | \
  gcloud secrets versions add dev-gke-dex-github-client-secret --data-file=-
```

External Secrets picks it up within an hour; to apply it right away:
`kubectl -n auth annotate externalsecret dex-secrets force-sync=$(date +%s) --overwrite`.

Watch the rollout:

```bash
gcloud container clusters get-credentials dev-gke --region asia-south1 \
  --project boreal-conquest-421512 --dns-endpoint
kubectl -n argocd get applications
```

## Using the UIs

Everything is internal (`*.dev.stack.internal`). From your laptop, open a SOCKS
proxy through the IAP bastion and point a browser at it:

```bash
gcloud compute ssh dev-gke-bastion --zone asia-south1-a \
  --project boreal-conquest-421512 --tunnel-through-iap -- -N -D 1080
# Windows (Git Bash):
"/c/Program Files/Google/Chrome/Application/chrome.exe" \
  --proxy-server="socks5://localhost:1080" --user-data-dir="/c/temp/gke-proxy"
```

| URL | |
|---|---|
| http://argocd.dev.stack.internal | Argo CD |
| http://grafana.dev.stack.internal | Grafana |
| http://prometheus.dev.stack.internal | Prometheus |
| http://alertmanager.dev.stack.internal | Alertmanager |
| http://gpm.dev.stack.internal | Gatekeeper Policy Manager |

All sign in with GitHub.

## Day 2

- **Add/remove a user**: edit `auth.admins` / `auth.viewers` → PR → merge.
- **Upgrade an add-on**: bump its version in `platform/apps/values.yaml` → PR.
- **Deploy an app**: add `workloads/<app>/base` + `workloads/<app>/overlays/dev`
  (see `workloads/hello`). It appears in Argo CD as `<app>`, namespace `<app>`.
- **Turn policies on**: when Policy Manager shows no violations, set
  `policies.enforcementAction: deny`.
- **Slack alerts**: `enable_slack_alerts = true` (Terraform) + `alerting.slack.enabled: true`,
  then add the webhook URL to `dev-gke-alertmanager-slack-webhook`.
- **Rotate a generated secret**: bump `secret_data_wo_version` in
  `modules/gke-cluster/secrets.tf`.
- **Break-glass**: Argo CD has no local admin. Cluster admins use `kubectl` (IAM).
  Grafana's admin password is in `dev-gke-grafana-admin-password`.

## Add a cluster

1. `cp -r live/dev live/prod`; edit `main.tf` (name, domain, CIDRs, node pools)
   and `backend.hcl` (`prefix = "live/prod"`).
2. `cp platform/clusters/dev-gke.yaml platform/clusters/prod-gke.yaml` and edit.
3. Add `prod` to the matrices in `.github/workflows/terraform.yml` and to
   `github_environments` in `bootstrap/terraform.tfvars` (re-apply bootstrap).
4. Create the `prod` GitHub Environment with required reviewers. Add a
   `workloads/*/overlays/prod` for each app that should run there.

## Tear down

Remove platform load balancers **before** destroying the cluster, otherwise
GKE-created LB resources block VPC deletion:

```bash
kubectl -n argocd delete application root      # cascades to every add-on
kubectl -n envoy-gateway-system get svc         # wait until the LB service is gone
# then set deletion_protection = false in live/<env>/main.tf, apply, and destroy
```

## Known gaps (deliberate, for now)

- **HTTP only.** Traffic stays inside the VPC, but logins are unencrypted on the
  wire. Next step: cert-manager with an internal CA (or a real domain + Let's
  Encrypt), then `cookie_secure = true`.
- **No default-deny NetworkPolicies** yet; add per namespace once traffic flows are known.
- GitHub Actions are pinned to major versions; pin to commit SHAs for supply-chain hardening.


Fix

Run google-github-actions/auth@v3
Created credentials file at "/home/runner/work/terraform-google-gke/terraform-google-gke/gha-creds-aa191fd072d93b05.json"
Error: google-github-actions/auth failed with: failed to generate Google Cloud OAuth 2.0 Access Token for gha-terraform-apply@boreal-conquest-421512.iam.gserviceaccount.com: {
  "error": {
    "code": 403,
    "message": "Permission 'iam.serviceAccounts.getAccessToken' denied on resource (or it may not exist). Remediate access with this Troubleshooter URL or share it with your administrator - https://console.cloud.google.com/iam-admin/troubleshooter/summary;errorId=CiQwMWExYjFmZS1kNWI1LTcwYmItYTUxZS0xNmZjYjgxMWU4ZTQSAA%3D%3D .",
    "status": "PERMISSION_DENIED",
    "details": [
      {
        "@type": "type.googleapis.com/google.rpc.ErrorInfo",
        "reason": "IAM_PERMISSION_DENIED",
        "domain": "iam.googleapis.com",
        "metadata": {
          "troubleshooter_url": "https://console.cloud.google.com/iam-admin/troubleshooter/summary;errorId=CiQwMWExYjFmZS1kNWI1LTcwYmItYTUxZS0xNmZjYjgxMWU4ZTQSAA%3D%3D",
          "permission": "iam.serviceAccounts.getAccessToken",
          "error_info_id": "CiQwMWExYjFmZS1kNWI1LTcwYmItYTUxZS0xNmZjYjgxMWU4ZTQSAA=="
        }
      }
    ]
  }
}

resource "google_service_account_iam_member" "apply_wif" {
  service_account_id = google_service_account.apply.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.ref/refs/heads/main"
}

correctly update it
