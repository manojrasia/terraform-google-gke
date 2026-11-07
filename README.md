# GKE platform (private cluster + GitOps)

Regional GKE clusters with private nodes in `asia-south1`, built with Terraform from GitHub
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
3. Argo CD installs everything else from Git. Sync waves only order **creation**;
   no app waits for another to become Healthy. Every app retries forever (20s → 3m
   backoff) until what it needs exists (CRDs, secrets, other services). One slow or
   broken add-on therefore never blocks the rest - the whole platform converges
   in ~10-15 minutes on a fresh cluster with no manual steps.
4. Every later change is a pull request. Argo CD reverts manual `kubectl` edits.

| Concern | How it's handled |
|---|---|
| CI credentials | WIF: PRs get a read-only SA; only jobs in a GitHub Environment can use the apply SA |
| Secrets | Secret Manager → External Secrets (Workload Identity). Nothing secret in Git or state |
| Login | Dex + GitHub. No local users; Argo CD admin disabled; Grafana login form disabled |
| Authorization | Only emails in `platform/clusters/<cluster>.yaml` get in (Argo CD RBAC, Grafana roles, oauth2-proxy allowlist) |
| Cluster access | IAM (`cluster_admins`/`cluster_developers` in `live/<env>/main.tf`) over the DNS endpoint |
| Network | Private nodes, Cloud NAT egress (static IP). UIs on an internal **or** public LB - one switch, see below |
| Least privilege | Node SA minimal; ExternalDNS can edit only its zone; ESO can read only its cluster's secrets |
| HA | Regional control plane, nodes in 3 zones, 2+ replicas and PDBs for every add-on, Argo CD HA Redis |
| Policy | Gatekeeper: owner label, no privileged, requests/limits, no `latest` (start `dryrun`) |
| Upgrades | Chart versions pinned in `platform/apps/values.yaml`; Dependabot for actions + providers |

## Internal or public: one switch

In `live/<env>/main.tf`:

```hcl
ingress_exposure = "public"     # or "internal"
```

| | `internal` | `public` |
|---|---|---|
| Load balancer | GCP internal LB (VPC only) | GCP external LB on a reserved static IP |
| Hostnames | `argocd.dev.stack.internal` (private Cloud DNS + ExternalDNS) | `argocd.<ip-with-dashes>.sslip.io` - no DNS setup at all. Or set `public_domain` to a domain you own |
| From your laptop | bastion SOCKS proxy (below) | just open the URL |
| Who can connect | anyone in the VPC | `public_ingress_allowed_cidrs` (+ the cluster's NAT IP, added automatically) |

Merge the change → CI runs `terraform apply`, then `bootstrap-argocd.sh` passes the
Terraform outputs (`platform_values`: domain, exposure, IPs) to the `root` app,
and Argo CD re-points the gateway, Dex, Grafana, oauth2-proxy and every app route.
Nothing else to edit. Both static IPs stay reserved, so you can switch back and forth.

**If the domain changes** (switching modes, or a new public IP after a full
destroy), update the GitHub OAuth App with the values from
`terraform output github_oauth_app`.

**Control plane:** kubectl already works from anywhere via the IAM-protected DNS
endpoint (`--dns-endpoint`). `public_control_plane = true` additionally enables
the classic public IP endpoint, limited to `master_authorized_networks`.
Nodes always stay private.

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

The URLs depend on the domain, which Terraform picks. Get them once the first
apply has run (the CI job prints them, or locally):

```bash
terraform -chdir=live/dev output github_oauth_app
```

GitHub → **Settings → Developer settings → OAuth Apps → New OAuth App**, and use
`homepage_url` and `callback_url` from that output. Until the app exists, everything
except login works; Dex and oauth2-proxy simply retry.

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

```bash
terraform -chdir=live/dev output urls
```

**Public mode:** open those URLs directly. Nothing else needed.

**Internal mode:** the IPs only exist inside the VPC (a hosts file entry on your
laptop cannot work). Open a SOCKS proxy through the IAP bastion and point a
browser at it; DNS is resolved on the bastion side, so the names just work:

```bash
gcloud compute ssh dev-gke-bastion --zone asia-south1-a \
  --project boreal-conquest-421512 --tunnel-through-iap -- -N -D 1080
# Windows (Git Bash):
"/c/Program Files/Google/Chrome/Application/chrome.exe" \
  --proxy-server="socks5://localhost:1080" --user-data-dir="/c/temp/gke-proxy"
```

Argo CD, Grafana, Prometheus, Alertmanager and Gatekeeper Policy Manager all sign
in with GitHub. Apps under `workloads/` get `http://<app>.<domain>` automatically.

## Troubleshooting

```bash
kubectl -n argocd get applications
# why one app is not Synced/Healthy:
kubectl -n argocd get application <app> -o jsonpath='{.status.operationState.message}{"\n"}{range .status.conditions[*]}{.type}: {.message}{"\n"}{end}'
# which routes have no backend yet:
kubectl get httproute -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,HOST:.spec.hostnames[0],RESOLVED:.status.parents[*].conditions[?(@.type=="ResolvedRefs")].status'
kubectl -n envoy-gateway-system get svc        # EXTERNAL-IP = the gateway IP
```

| Symptom | Cause |
|---|---|
| `dex` / `oauth2-proxy-*` not Healthy | GitHub client secret not in Secret Manager yet (`kubectl -n auth get externalsecret` says so) |
| Route works on `argocd`, 500 on others | that app is still installing - wait, it retries on its own |
| Browser can't reach anything (internal) | use the SOCKS proxy; the internal LB IP is not routable from home |
| Browser can't reach anything (public) | your IP is not in `public_ingress_allowed_cidrs` |
| Login loops back / `redirect_uri` error | GitHub OAuth App URLs don't match `terraform output github_oauth_app` |

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
# dev has deletion_protection = false; then: terraform -chdir=live/dev destroy
```

## Known gaps (deliberate, for now)

- **HTTP only.** In `internal` mode traffic stays in the VPC. In `public` mode
  logins and session cookies cross the internet unencrypted - keep
  `public_ingress_allowed_cidrs` to your own IP. Next step: cert-manager +
  Let's Encrypt (works with sslip.io or your domain), then `cookie_secure = true`.
- **No default-deny NetworkPolicies** yet; add per namespace once traffic flows are known.
- GitHub Actions are pinned to major versions; pin to commit SHAs for supply-chain hardening.


To access hello app

 kubectl -n envoy-gateway-system get svc   

 curl.exe -sI http://hello.34-47-167-37.sslip.io

 http://hello.34-47-167-37.sslip.io

 destroy all infra

 Use PowerShell from your repo folder.

1. Stop Argo CD from re-creating things
powershell
cd D:\terraform-google-gke-v3
git switch main; git pull
gcloud container clusters get-credentials dev-gke --region asia-south1 --project boreal-conquest-421512 --dns-endpoint

kubectl -n argocd scale deployment --all --replicas=0
kubectl -n argocd scale statefulset --all --replicas=0
kubectl -n envoy-gateway-system scale deployment envoy-gateway --replicas=0
2. Delete the load balancer(s)
powershell
kubectl get svc -A --no-headers -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name,TYPE:.spec.type" |
  ForEach-Object { $c = -split $_; if ($c[2] -eq "LoadBalancer") { kubectl -n $c[0] delete svc $c[1] } }

Wait 1–3 minutes until this shows nothing:

powershell
gcloud compute forwarding-rules list --project boreal-conquest-421512
3. Destroy the infrastructure
powershell
gcloud auth application-default login     # Terraform uses your Owner account locally
terraform -chdir=live/dev init -backend-config=backend.hcl
terraform -chdir=live/dev destroy

Check the plan says it will destroy the cluster, VPC, NAT, bastion, IPs, DNS zone and secrets, then type yes. It takes about 10–15 minutes.

4. Delete leftover disks

Prometheus, Grafana and Alertmanager stored data on persistent disks. Those disks aren’t deleted with the cluster, and they keep costing money:

powershell
gcloud compute disks list --project boreal-conquest-421512 --filter="name~^pvc-"
gcloud compute disks list --project boreal-conquest-421512 --filter="name~^pvc-" --format="value(name,zone.basename())" |
  ForEach-Object { $d = -split $_; gcloud compute disks delete $d[0] --zone $d[1] --project boreal-conquest-421512 --quiet }

Final check:

powershell
gcloud container clusters list --project boreal-conquest-421512
gcloud compute addresses list --project boreal-conquest-421512
gcloud compute disks list --project boreal-conquest-421512

All three should be empty.
