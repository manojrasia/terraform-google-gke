# k8s-stack on private GKE (asia-south1)

Same stack as the kind version (Envoy Gateway, Prometheus/Grafana/Alertmanager,
Blackbox, pvc-autoresizer, Dex, oauth2-proxy x3, Argo CD, ExternalDNS,
Gatekeeper + Policy Manager, Wiz), adapted for the private GKE cluster.

## What changed vs kind

| kind | GKE |
|---|---|
| `cluster-1.yaml` (kind config) | removed – cluster comes from Terraform |
| Envoy on NodePort 30080 | Envoy on a GCP **internal load balancer** (private IP in gke-vpc) |
| `*.localtest.me` → 127.0.0.1 | `*.stack.internal` in a **private Cloud DNS zone** |
| CoreDNS rewrite for dex (`manifests/coredns.yaml`) | removed – pods resolve `dex.stack.internal` through Cloud DNS |
| ExternalDNS `inmemory` | ExternalDNS `google` provider using **Workload Identity** |
| Context `kind-cluster-1` | `gke_<project>_asia-south1_private-gke-cluster`, run from the bastion |
| node-exporter `hostRootFsMount: false` (Docker Desktop) | default (enabled) |
| Scrapes etcd/scheduler/controller-manager/kube-proxy/CoreDNS | disabled (managed by Google / Dataplane V2); scrapes **kube-dns** |
| Prometheus/Alertmanager without disks | 20Gi / 10Gi PVCs on `standard-autoresize` (pd-standard, auto-grown by pvc-autoresizer) |
| Wiz flavor `Kubernetes` | `GKE` |
| Gatekeeper exempts kube-system | also exempts `gmp-*` and `gke-*` namespaces |
| — | Firewall rule so the control plane can reach webhooks on 8443/9443 |

Hostnames are written as `__DOMAIN__` in `values/` and `manifests/`;
`install.sh` renders them into `.rendered/` (default domain `stack.internal`).

## 1. Terraform additions (run once)

Copy `terraform/stack.tf` into your Terraform folder and apply:

```bash
cd terraform
terraform plan -out tfplan && terraform apply tfplan
```

It creates the private DNS zone `stack.internal`, the `external-dns` Google
service account bound with Workload Identity, and the webhook firewall rule.

## 2. Prepare the bastion

```bash
gcloud compute ssh private-gke-cluster-bastion --zone asia-south1-a \
  --project boreal-conquest-421512 --tunnel-through-iap
```

On the bastion:

```bash
# Tools
sudo apt-get update
sudo apt-get install -y git openssl kubectl google-cloud-cli-gke-gcloud-auth-plugin
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Log in as YOURSELF (the bastion's service account can't create CRDs/ClusterRoles)
gcloud auth login --no-launch-browser
gcloud config set project boreal-conquest-421512

# Get the code
git clone https://github.com/manojrasia/terraform-google-gke.git
cd terraform-google-gke/k8s-stack
```

## 3. Install

```bash
PROJECT_ID=boreal-conquest-421512 ./install.sh
```

Optional: `DOMAIN=...` (must match `dns_domain` in Terraform),
`WIZ_CLIENT_ID`/`WIZ_CLIENT_TOKEN` (+ `WIZ_SENSOR_PULL_USER`/`_PASSWORD`).

To re-download charts: `./fetch-charts.sh` (works from the bastion through Cloud NAT).

## 4. Open the UIs from your laptop

Everything is internal. Open a SOCKS proxy through the bastion:

```bash
gcloud compute ssh private-gke-cluster-bastion --zone asia-south1-a \
  --project boreal-conquest-421512 --tunnel-through-iap -- -N -D 1080
```

Then start a browser that uses it (DNS is resolved on the bastion, so
`*.stack.internal` works):

```bash
# Chrome (Windows: use the full path to chrome.exe)
chrome --proxy-server="socks5://localhost:1080" --user-data-dir=/tmp/gke-proxy
```

Firefox: Settings → Network Settings → Manual proxy → SOCKS Host `localhost`,
port `1080`, SOCKS v5, and tick **Proxy DNS when using SOCKS v5**.

| URL | Login |
|---|---|
| http://grafana.stack.internal | admin / admin123 |
| http://prometheus.stack.internal | Dex: admin@example.com / password |
| http://alertmanager.stack.internal | Dex |
| http://gpm.stack.internal | Dex |
| http://argocd.stack.internal | Log in via Dex, or `admin` + password printed by install.sh |

## Sizing

Fits on 3 × e2-standard-2 nodes (autoscaling up to 2 per zone). GKE Managed
Prometheus is also enabled by Terraform; since you run your own Prometheus you
can turn it off to save resources (`managed_prometheus { enabled = false }`).

## Before using beyond a lab

Change the Grafana password, the Dex static user/hash and the client secrets
(`argocd-dex-secret`, `oauth2-proxy-dex-secret`), and consider TLS on the gateway.

## Remove the stack

```bash
PROJECT_ID=boreal-conquest-421512 ./uninstall.sh
```
