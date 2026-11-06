#!/usr/bin/env bash
# One-time (idempotent) GitOps bootstrap for a cluster:
#   1. installs Argo CD if it is not there yet
#   2. applies the "root" Application, after which Argo CD installs and manages everything else
#
# Usage:  scripts/bootstrap-argocd.sh platform/clusters/dev-gke.yaml
# Needs:  gcloud (+ gke-gcloud-auth-plugin), kubectl, helm, yq (mikefarah)
set -euo pipefail
cd "$(dirname "$0")/.."

CLUSTER_FILE="${1:?usage: $0 platform/clusters/<cluster>.yaml}"
APPS_VALUES=platform/apps/values.yaml

for bin in gcloud kubectl helm yq; do
  command -v "$bin" >/dev/null || { echo "missing: $bin"; exit 1; }
done

NAME=$(yq -r '.cluster.name' "$CLUSTER_FILE")
PROJECT=$(yq -r '.cluster.projectId' "$CLUSTER_FILE")
REGION=$(yq -r '.cluster.region' "$CLUSTER_FILE")
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
kubectl apply -f - <<YAML
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
        - ../clusters/$(basename "$CLUSTER_FILE")
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    retry:
      limit: 10
      backoff:
        duration: 30s
        factor: 2
        maxDuration: 10m
YAML

echo "==> Done. Watch progress: kubectl -n argocd get applications"
