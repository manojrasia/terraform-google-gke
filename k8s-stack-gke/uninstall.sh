#!/usr/bin/env bash
# Removes the stack (not the cluster). Run from the bastion.
set -uo pipefail
PROJECT_ID="${PROJECT_ID:?Set PROJECT_ID}"
REGION="${REGION:-asia-south1}"
CLUSTER_NAME="${CLUSTER_NAME:-private-gke-cluster}"
CTX="gke_${PROJECT_ID}_${REGION}_${CLUSTER_NAME}"
K="kubectl --context $CTX"; H="helm --kube-context $CTX"

$K delete -f .rendered/manifests/routes.yaml --ignore-not-found
for r in "wiz-integration wiz" "oauth2-proxy-gpm auth" "gatekeeper-policy-manager gatekeeper-system" \
         "gatekeeper gatekeeper-system" "argocd argocd" "oauth2-proxy-alertmanager auth" \
         "oauth2-proxy auth" "dex auth" "pvc-autoresizer monitoring" "blackbox-exporter monitoring" \
         "kube-prometheus-stack monitoring" "external-dns external-dns"; do
  set -- $r; $H uninstall "$1" -n "$2" 2>/dev/null
done
# Deleting the Gateway removes the internal load balancer
$K delete -f .rendered/manifests/gateway.yaml --ignore-not-found
$H uninstall eg -n envoy-gateway-system
$K delete pvc --all -n monitoring
echo "Done. DNS records left in Cloud DNS can be removed with terraform destroy (zone has force_destroy)."
