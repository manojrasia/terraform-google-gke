#!/usr/bin/env bash
# Installs the platform stack on the private GKE cluster.
#
# Run it FROM THE BASTION (the control plane only has an internal IP):
#   PROJECT_ID=boreal-conquest-421512 ./install.sh
#
# Optional overrides: REGION, CLUSTER_NAME, DOMAIN
# Wiz (optional):     WIZ_CLIENT_ID, WIZ_CLIENT_TOKEN, WIZ_SENSOR_PULL_USER, WIZ_SENSOR_PULL_PASSWORD
set -euo pipefail
cd "$(dirname "$0")"

PROJECT_ID="${PROJECT_ID:?Set PROJECT_ID, e.g.  PROJECT_ID=my-project ./install.sh}"
REGION="${REGION:-asia-south1}"
CLUSTER_NAME="${CLUSTER_NAME:-private-gke-cluster}"
DOMAIN="${DOMAIN:-stack.internal}"
CTX="gke_${PROJECT_ID}_${REGION}_${CLUSTER_NAME}"

for bin in kubectl helm gcloud openssl curl; do
  command -v "$bin" >/dev/null || { echo "Missing '$bin'. See README-GKE.md (bastion setup)."; exit 1; }
done
[[ -d charts ]] || { echo "No ./charts folder. Run ./fetch-charts.sh first."; exit 1; }

echo "==> Cluster credentials ($CTX)"
if ! kubectl config get-contexts "$CTX" >/dev/null 2>&1; then
  gcloud container clusters get-credentials "$CLUSTER_NAME" \
    --region "$REGION" --project "$PROJECT_ID" --internal-ip
fi
K="kubectl --context $CTX"
H="helm --kube-context $CTX"
$K get nodes

echo "==> Rendering values/manifests for domain $DOMAIN"
R=.rendered
rm -rf "$R" && mkdir -p "$R" && cp -r values manifests "$R/"
find "$R" -type f -name '*.yaml' -exec sed -i \
  -e "s|__DOMAIN__|$DOMAIN|g" \
  -e "s|__PROJECT_ID__|$PROJECT_ID|g" \
  -e "s|__CLUSTER_NAME__|$CLUSTER_NAME|g" {} +
V="$R/values"; M="$R/manifests"

echo "==> Namespaces"
for ns in envoy-gateway-system external-dns monitoring auth argocd gatekeeper-system wiz; do
  $K create namespace "$ns" --dry-run=client -o yaml | $K apply -f -
  $K label namespace "$ns" owner=platform --overwrite >/dev/null
done

echo "==> StorageClass (pd-standard, expandable)"
$K apply -f "$M/storageclass.yaml"

echo "==> Envoy Gateway (internal load balancer)"
$H upgrade --install eg charts/gateway-helm \
  -n envoy-gateway-system --wait --timeout 10m
$K apply -f "$M/gateway.yaml"

echo "Waiting for the internal load balancer IP..."
GW_IP=""
for _ in $(seq 1 60); do
  GW_IP=$($K -n envoy-gateway-system get gateway main -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)
  [[ -n "$GW_IP" ]] && break
  sleep 10
done
[[ -n "$GW_IP" ]] || { echo "Gateway has no IP after 10 min. Check: $K -n envoy-gateway-system get svc"; exit 1; }
echo "Gateway internal IP: $GW_IP"

echo "==> ExternalDNS (Cloud DNS private zone, Workload Identity)"
$H upgrade --install external-dns charts/external-dns \
  -n external-dns -f "$V/external-dns.yaml" --wait --timeout 5m

echo "==> Routes"
$K apply -f "$M/routes.yaml"

echo "==> Prometheus + Grafana"
$H upgrade --install kube-prometheus-stack charts/kube-prometheus-stack \
  -n monitoring -f "$V/kube-prometheus-stack.yaml" --wait --timeout 15m

echo "==> Blackbox exporter"
$H upgrade --install blackbox-exporter charts/prometheus-blackbox-exporter \
  -n monitoring -f "$V/blackbox-exporter.yaml" --wait --timeout 5m

echo "==> PVC autoresizer"
$H upgrade --install pvc-autoresizer charts/pvc-autoresizer \
  -n monitoring -f "$V/pvc-autoresizer.yaml" --wait --timeout 5m

echo "==> Dex"
$H upgrade --install dex charts/dex \
  -n auth -f "$V/dex.yaml" --wait --timeout 5m

# oauth2-proxy and Argo CD need http://dex.$DOMAIN to resolve at startup.
# On GKE that happens via ExternalDNS -> Cloud DNS -> internal LB.
echo "Waiting for http://dex.$DOMAIN to answer (DNS record + gateway)..."
DEX_OK=""
for _ in $(seq 1 60); do
  if curl -fsS -m 5 "http://dex.$DOMAIN/dex/.well-known/openid-configuration" >/dev/null 2>&1; then
    DEX_OK=yes; break
  fi
  sleep 10
done
[[ -n "$DEX_OK" ]] || {
  echo "dex.$DOMAIN not reachable after 10 min."
  echo "Check: gcloud dns record-sets list --zone $(echo "$DOMAIN" | tr . -) --project $PROJECT_ID"
  echo "       $K -n external-dns logs deploy/external-dns"
  exit 1
}

echo "==> oauth2-proxy (Prometheus)"
$H upgrade --install oauth2-proxy charts/oauth2-proxy \
  -n auth -f "$V/oauth2-proxy.yaml" \
  --set config.cookieSecret="$(openssl rand -hex 16)" --wait --timeout 5m

echo "==> oauth2-proxy (Alertmanager)"
$H upgrade --install oauth2-proxy-alertmanager charts/oauth2-proxy \
  -n auth -f "$V/oauth2-proxy-alertmanager.yaml" \
  --set config.cookieSecret="$(openssl rand -hex 16)" --wait --timeout 5m

echo "==> Argo CD"
$H upgrade --install argocd charts/argo-cd \
  -n argocd -f "$V/argocd.yaml" --wait --timeout 10m

echo "==> OPA Gatekeeper"
$H upgrade --install gatekeeper charts/gatekeeper \
  -n gatekeeper-system -f "$V/gatekeeper.yaml" --wait --timeout 10m
$K apply -f "$M/gatekeeper/templates.yaml"
echo "Waiting for constraint CRDs..."
for crd in k8srequiredlabels k8spspprivilegedcontainer; do
  for _ in $(seq 1 60); do
    $K get crd "$crd.constraints.gatekeeper.sh" >/dev/null 2>&1 && break
    sleep 2
  done
  $K wait --for=condition=established "crd/$crd.constraints.gatekeeper.sh" --timeout=60s
done
$K apply -f "$M/gatekeeper/constraints.yaml"
$K apply -f "$M/gatekeeper/podmonitor.yaml"

echo "==> Gatekeeper Policy Manager (UI)"
$H upgrade --install gatekeeper-policy-manager charts/gatekeeper-policy-manager \
  -n gatekeeper-system -f "$V/gatekeeper-policy-manager.yaml" --wait --timeout 5m
$H upgrade --install oauth2-proxy-gpm charts/oauth2-proxy \
  -n auth -f "$V/oauth2-proxy-gpm.yaml" \
  --set config.cookieSecret="$(openssl rand -hex 16)" --wait --timeout 5m

echo "==> Wiz (Connector, Sensor, Admission Controller)"
if [[ -n "${WIZ_CLIENT_ID:-}" && -n "${WIZ_CLIENT_TOKEN:-}" ]]; then
  WIZ_ARGS=(
    --set global.wizApiToken.clientId="$WIZ_CLIENT_ID"
    --set global.wizApiToken.clientToken="$WIZ_CLIENT_TOKEN"
  )
  if [[ -n "${WIZ_SENSOR_PULL_USER:-}" && -n "${WIZ_SENSOR_PULL_PASSWORD:-}" ]]; then
    WIZ_ARGS+=(
      --set wiz-sensor.imagePullSecret.username="$WIZ_SENSOR_PULL_USER"
      --set wiz-sensor.imagePullSecret.password="$WIZ_SENSOR_PULL_PASSWORD"
    )
  else
    echo "No sensor pull credentials: installing Wiz without the Sensor."
    WIZ_ARGS+=(--set wiz-sensor.enabled=false)
  fi
  $H upgrade --install wiz-integration charts/wiz-kubernetes-integration \
    -n wiz -f "$V/wiz.yaml" "${WIZ_ARGS[@]}" --wait --timeout 10m
else
  echo "Skipping Wiz: set WIZ_CLIENT_ID and WIZ_CLIENT_TOKEN to install it."
fi

echo
echo "Done. Gateway internal IP: $GW_IP"
echo "These URLs work from inside gke-vpc (bastion, VPN, or the SOCKS proxy in README-GKE.md):"
echo "  http://grafana.$DOMAIN       (admin / admin123)"
echo "  http://prometheus.$DOMAIN    (Dex login: admin@example.com / password)"
echo "  http://alertmanager.$DOMAIN  (Dex login)"
echo "  http://gpm.$DOMAIN           (Gatekeeper UI, Dex login)"
echo "  http://argocd.$DOMAIN        (LOG IN VIA DEX, or admin + password below)"
echo "  http://dex.$DOMAIN/dex/.well-known/openid-configuration"
echo
echo -n "Argo CD local admin password: "
$K -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
echo
