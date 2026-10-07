#!/usr/bin/env bash
# =============================================================================
# local-dashboard-up.sh — Deploie l'UI Kubernetes Headlamp sur le cluster Kind local.
#
# Usage :
#   ./scripts/local-dashboard-up.sh
#   SKIP_FORWARD=1 ./scripts/local-dashboard-up.sh
#
# Cf. rncp_soutenance/INVENTAIRE_ACCES_LOCAL.md.
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

CLUSTER="${CLUSTER:-crypto-bot}"
CTX="kind-${CLUSTER}"
NS="headlamp"
RELEASE="${RELEASE:-headlamp}"
CHART_VERSION="${CHART_VERSION:-0.45.0}"
PORT="${PORT:-8090}"

info() { printf '\n\033[36m>>> %s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }

for bin in docker kind kubectl helm; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERREUR : '$bin' introuvable." >&2; exit 1; }
done
if ! kubectl --context "$CTX" cluster-info >/dev/null 2>&1; then
  echo "ERREUR : contexte '${CTX}' injoignable. Lancez d'abord ./scripts/local-up.sh" >&2
  exit 1
fi

info "1/3  Depot Helm + installation de Headlamp v${CHART_VERSION}"
helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/ >/dev/null 2>&1 || true
helm repo update headlamp >/dev/null
helm --kube-context "$CTX" upgrade --install "$RELEASE" headlamp/headlamp \
  --namespace "$NS" --create-namespace \
  --version "$CHART_VERSION" \
  -f overlays/local-dashboard/values.yaml \
  --wait --timeout 5m
ok "release '${RELEASE}' deployee (ClusterRoleBinding cluster-admin cree)"

info "2/3  Etat"
kubectl --context "$CTX" -n "$NS" get pods,svc

info "3/3  Port-forward (Ctrl+C pour arreter)"
if [ "${SKIP_FORWARD:-0}" = "1" ]; then
  echo "  ignore (SKIP_FORWARD=1). Lancez : kubectl --context ${CTX} -n ${NS} port-forward svc/headlamp ${PORT}:80"
  exit 0
fi

pkill -f "port-forward.*-n ${NS}.*svc/headlamp" 2>/dev/null || true

cleanup() { kill $(jobs -p) 2>/dev/null || true; }
trap cleanup INT TERM

kubectl --context "$CTX" -n "$NS" port-forward svc/headlamp "${PORT}:80" >/dev/null 2>&1 &
sleep 3

echo
echo "  Headlamp (UI Kubernetes) → http://localhost:${PORT}"
echo
echo "Ctrl+C pour arreter."
wait
