#!/usr/bin/env bash
# =============================================================================
# local-monitoring-up.sh — Deploie Prometheus + Grafana (+ Alertmanager,
# node-exporter, kube-state-metrics) sur le cluster Kind local.
#
# Usage :
#   ./scripts/local-monitoring-up.sh
#   CLUSTER=autre ./scripts/local-monitoring-up.sh
#   SKIP_FORWARD=1 ./scripts/local-monitoring-up.sh   # pas de port-forward a la fin
#
# Prerequis : le cluster Kind doit exister (./scripts/local-up.sh).
# Cf. rncp_soutenance/PLAN_MONITORING_LOCAL.md.
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

CLUSTER="${CLUSTER:-crypto-bot}"
CTX="kind-${CLUSTER}"
NS="monitoring"
RELEASE="${RELEASE:-monitoring}"
CHART_VERSION="${CHART_VERSION:-92.1.0}"

info() { printf '\n\033[36m>>> %s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }

for bin in docker kind kubectl helm; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERREUR : '$bin' introuvable dans le PATH." >&2; exit 1; }
done

if ! kubectl --context "$CTX" cluster-info >/dev/null 2>&1; then
  echo "ERREUR : contexte '${CTX}' injoignable. Lancez d'abord ./scripts/local-up.sh" >&2
  exit 1
fi

info "1/4  Depot Helm + secret/namespace"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update prometheus-community >/dev/null
kubectl --context "$CTX" apply -k overlays/local-monitoring
ok "namespace '${NS}' + secret grafana-admin"

info "2/4  Installation kube-prometheus-stack v${CHART_VERSION}"
helm --kube-context "$CTX" upgrade --install "$RELEASE" \
  prometheus-community/kube-prometheus-stack \
  --namespace "$NS" --create-namespace \
  --version "$CHART_VERSION" \
  -f overlays/local-monitoring/values.yaml \
  --wait --timeout 10m
ok "release '${RELEASE}' deployee"

info "3/4  Etat des pods"
kubectl --context "$CTX" -n "$NS" get pods

info "4/4  Port-forward (Ctrl+C pour arreter les forwards)"
if [ "${SKIP_FORWARD:-0}" = "1" ]; then
  echo "  ignore (SKIP_FORWARD=1)."
  echo "  Grafana    : kubectl --context ${CTX} -n ${NS} port-forward svc/monitoring-grafana 3000:80"
  echo "  Prometheus : kubectl --context ${CTX} -n ${NS} port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090"
  exit 0
fi

# Coupe d'anciens forwards monitoring (ne touche pas aux forwards applicatifs).
pkill -f "port-forward.*-n monitoring" 2>/dev/null && sleep 1 || true

cleanup() { kill $(jobs -p) 2>/dev/null || true; }
trap cleanup INT TERM

kubectl --context "$CTX" -n "$NS" port-forward svc/monitoring-grafana 3000:80 >/dev/null 2>&1 &
kubectl --context "$CTX" -n "$NS" port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 >/dev/null 2>&1 &
kubectl --context "$CTX" -n "$NS" port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093 >/dev/null 2>&1 &
sleep 3

echo
echo "  Grafana      → http://localhost:3000   (admin / admin)"
echo "  Prometheus   → http://localhost:9090   (targets: http://localhost:9090/targets)"
echo "  Alertmanager → http://localhost:9093"
echo
echo "Ctrl+C pour arreter."
wait
