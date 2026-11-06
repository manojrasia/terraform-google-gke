# Private (internal) Standard GKE cluster – asia-south1

Terraform code that creates:

- Custom VPC + regional subnet in `asia-south1` with secondary ranges for pods and services
- Cloud Router + Cloud NAT (egress for private nodes)
- **Private Standard GKE cluster** (regional, private nodes, private control-plane endpoint)
- **Workload Identity** enabled (`<project>.svc.id.goog`, nodes in `GKE_METADATA` mode)
- Dataplane V2, Shielded nodes, Managed Prometheus, maintenance window
- Separate autoscaling node pool with a least-privilege node service account
- Optional internal bastion VM (no public IP, SSH via IAP) to run `kubectl`
- Optional GSA ↔ KSA Workload Identity bindings

## Network layout

| Range         | CIDR            | Purpose                 |
|---------------|-----------------|-------------------------|
| Subnet        | 10.10.0.0/20    | Nodes, bastion          |
| Pods          | 10.20.0.0/16    | Pod IPs                 |
| Services      | 10.30.0.0/20    | ClusterIP services      |
| Control plane | 172.16.0.0/28   | GKE master (peered)     |

## Prerequisites

- Terraform >= 1.5, gcloud CLI
- Your user needs (on the project): `roles/container.admin`, `roles/compute.networkAdmin`,
  `roles/compute.securityAdmin`, `roles/compute.instanceAdmin.v1`, `roles/iam.serviceAccountAdmin`,
  `roles/iam.serviceAccountUser`, `roles/resourcemanager.projectIamAdmin`, `roles/serviceusage.serviceUsageAdmin`
  (or simply Owner on a dev project)
- To SSH via IAP: `roles/iap.tunnelResourceAccessor` and `roles/compute.osAdminLogin`

## Usage

```bash
gcloud auth application-default login
cp terraform.tfvars.example terraform.tfvars   # edit project_id etc.
# optional: cp backend.tf.example backend.tf    # remote state in GCS

terraform init
terraform plan -out tfplan
terraform apply tfplan

gcloud auth login
gcloud auth application-default login
gcloud config set project boreal-conquest-421512
cp terraform.tfvars.example terraform.tfvars   # edit project_id
terraform init && terraform plan -out tfplan && terraform apply tfplan

```

Cluster creation takes ~10–15 minutes.

## Access the cluster (private endpoint)

```bash
# 1. SSH to the bastion through IAP
$(terraform output -raw bastion_ssh_command)

# 2. On the bastion
gcloud container clusters get-credentials private-gke-cluster \
  --region asia-south1 --internal-ip
kubectl get nodes
```

If you have VPN/Interconnect into the VPC, add your range to `master_authorized_networks` and run kubectl directly.

## Test Workload Identity

With the example binding in `terraform.tfvars.example` (`app-gsa` → `default/app-ksa`):

```bash
kubectl create serviceaccount app-ksa -n default
kubectl annotate serviceaccount app-ksa -n default \
  iam.gke.io/gcp-service-account=app-gsa@<PROJECT_ID>.iam.gserviceaccount.com

kubectl run wi-test -n default --rm -it \
  --image=google/cloud-sdk:slim \
  --overrides='{"spec":{"serviceAccountName":"app-ksa"}}' \
  -- gcloud auth list
```

The active account shown should be `app-gsa@<PROJECT_ID>.iam.gserviceaccount.com`.

## Destroy

`deletion_protection = true` by default. Set it to `false`, `terraform apply`, then `terraform destroy`.

P=boreal-conquest-421512
ME=$(gcloud config get-value account)

gcloud projects add-iam-policy-binding $P --member="user:$ME" --role="roles/iap.tunnelResourceAccessor"
gcloud projects add-iam-policy-binding $P --member="user:$ME" --role="roles/compute.osAdminLogin"

# Make sure the tools are installed (the startup script normally does this)
sudo apt-get install -y kubectl google-cloud-cli-gke-gcloud-auth-plugin

gcloud container clusters get-credentials private-gke-cluster \
  --region asia-south1 \
  --project boreal-conquest-421512 \
  --internal-ip

kubectl get nodes

