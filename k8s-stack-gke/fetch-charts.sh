#!/usr/bin/env bash
# Downloads every Helm chart the stack uses into ./charts (unpacked),
# so install.sh installs from local folders instead of remote repos.
# Run from Git Bash:  ./fetch-charts.sh
#
# To pin a version, put it after the chart, e.g. "argo/argo-cd 7.7.0".
# Leave it empty to get the latest. Versions you got are saved in charts/VERSIONS.txt.
set -euo pipefail
cd "$(dirname "$0")"

CHARTS=(
  "oci://docker.io/envoyproxy/gateway-helm"
  "prometheus-community/kube-prometheus-stack"
  "prometheus-community/prometheus-blackbox-exporter"
  "topolvm/pvc-autoresizer"
  "dex/dex"
  "oauth2-proxy/oauth2-proxy"
  "argo/argo-cd"
  "external-dns/external-dns"
  "gatekeeper/gatekeeper"
  "gpm/gatekeeper-policy-manager"
  "wiz-sec/wiz-kubernetes-integration"
)

echo "==> Adding Helm repos"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm repo add dex https://charts.dexidp.io --force-update
helm repo add oauth2-proxy https://oauth2-proxy.github.io/manifests --force-update
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/ --force-update
helm repo add topolvm https://topolvm.github.io/pvc-autoresizer --force-update
helm repo add wiz-sec https://wiz-sec.github.io/charts --force-update
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts --force-update
helm repo add gpm https://sighupio.github.io/gatekeeper-policy-manager --force-update
helm repo update

mkdir -p charts
: > charts/VERSIONS.txt

for entry in "${CHARTS[@]}"; do
  read -r ref version <<< "$entry"
  name="${ref##*/}"
  echo "==> $name ${version:-(latest)}"
  rm -rf "charts/$name"
  if [[ -n "${version:-}" ]]; then
    helm pull "$ref" --version "$version" --untar --untardir charts
  else
    helm pull "$ref" --untar --untardir charts
  fi
  got=$(grep -m1 '^version:' "charts/$name/Chart.yaml" | awk '{print $2}')
  echo "$name $got" >> charts/VERSIONS.txt
done

echo
echo "Downloaded charts:"
cat charts/VERSIONS.txt
