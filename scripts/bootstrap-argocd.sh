#!/usr/bin/env bash
# GitOps bootstrap for a cluster. Idempotent - CI runs it after every terraform apply.
#   1. installs Argo CD if it is not there yet (after that Argo CD manages itself from Git)
#   2. applies the "root" Application with the Terraform outputs (domain, exposure, IPs)
#      as values, so switching ingress_exposure in Terraform re-points everything
#
# Usage:  scripts/bootstrap-argocd.sh live/dev
#         (live/<env> must be `terraform init`-ed: CI already is; locally run
#          terraform -chdir=live/dev init -backend-config=backend.hcl first)
# Needs:  terraform, gcloud (+ gke-gcloud-auth-plugin), kubectl, helm, yq (mikefarah v4)
set -euo pipefail
cd "$(dirname "$0")/.."

ENV_DIR="${1:?usage: $0 live/<env>}"
ENV_DIR="${ENV_DIR%/}"
APPS_VALUES=platform/apps/values.yaml

for bin in terraform gcloud kubectl helm yq; do
  command -v "$bin" >/dev/null || { echo "missing: $bin"; exit 1; }
done

echo "==> Reading Terraform outputs from $ENV_DIR"
TF_OUT=$(mktemp); trap 'rm -f "$TF_OUT" "$TF_OUT.values"' EXIT
terraform -chdir="$ENV_DIR" output -json > "$TF_OUT"
yq -p json -o yaml '.platform_values.value' "$TF_OUT" > "$TF_OUT.values"
NAME=$(yq -p json -o yaml -r '.cluster.value.name' "$TF_OUT")
REGION=$(yq -p json -o yaml -r '.cluster.value.location' "$TF_OUT")

CLUSTER_FILE="platform/clusters/${NAME}.yaml"
[ -f "$CLUSTER_FILE" ] || { echo "missing $CLUSTER_FILE"; exit 1; }
PROJECT=$(yq -r '.cluster.projectId' "$CLUSTER_FILE")
REPO_URL=$(yq -r '.repoURL' "$APPS_VALUES")
REVISION="${TARGET_REVISION:-$(yq -r '.targetRevision' "$APPS_VALUES")}"
ARGOCD_VERSION=$(yq -r '.addons.argocd.version' "$APPS_VALUES")

echo "==> Credentials for $NAME (DNS endpoint)"
gcloud container clusters get-credentials "$NAME" \
  --region "$REGION" --project "$PROJECT" --dns-endpoint

if kubectl -n argocd get deployment argocd-server >/dev/null 2>&1; then
  echo "==> Argo CD already installed - it manages itself from Git, skipping helm"
else
  echo "==> Installing Argo CD $ARGOCD_VERSION"
  helm upgrade --install argocd argo-cd \
    --repo https://argoproj.github.io/argo-helm --version "$ARGOCD_VERSION" \
    --namespace argocd --create-namespace \
    -f platform/values/argocd.yaml \
    --wait --timeout 15m
fi

echo "==> Applying root Application ($REPO_URL @ $REVISION)"
cat <<YAML | VALUES="$TF_OUT.values" yq '.spec.source.helm.valuesObject = load(strenv(VALUES))' | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ${REPO_URL}
    targetRevision: ${REVISION}
    path: platform/apps
    helm:
      valueFiles:
        - ../clusters/${NAME}.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    retry:
      limit: -1
      backoff:
        duration: 20s
        factor: 2
        maxDuration: 3m
YAML

# A previous run may have left root stuck in an old failed operation: restart it cleanly.
PHASE=$(kubectl -n argocd get application root -o jsonpath='{.status.operationState.phase}' 2>/dev/null || true)
if [ "$PHASE" = "Failed" ] || [ "$PHASE" = "Error" ]; then
  echo "==> root's last sync was $PHASE - starting a fresh sync"
  kubectl -n argocd patch application root --type merge \
    -p '{"operation":{"initiatedBy":{"username":"bootstrap"},"sync":{"prune":true}}}'
fi

echo
echo "==> Done. Exposure: $(yq -r '.ingress.exposure' "$TF_OUT.values"), domain: $(yq -r '.cluster.domain' "$TF_OUT.values")"
echo "    Watch:  kubectl -n argocd get applications -w"
yq -p json -o yaml -r '.urls.value | to_entries | .[] | "    " + .value' "$TF_OUT" 2>/dev/null || true
