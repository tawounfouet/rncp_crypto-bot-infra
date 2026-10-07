#!/usr/bin/env bash
# =============================================================================
# local-monitoring-down.sh — Supprime la stack de monitoring local.
#
# Usage :
#   ./scripts/local-monitoring-down.sh            # uninstall + supprime le namespace
#   ./scripts/local-monitoring-down.sh --keep-ns  # uninstall seulement
#
# Note : les CRD de kube-prometheus-stack (cluster-scoped) ne sont pas supprimees
# (comportement Helm). Pour un nettoyage total du cluster, utiliser local-down.sh --purge.
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

CLUSTER="${CLUSTER:-crypto-bot}"
CTX="kind-${CLUSTER}"
NS="monitoring"
RELEASE="${RELEASE:-monitoring}"
KEEP_NS="${1:-}"

pkill -f "port-forward.*-n monitoring" 2>/dev/null && echo "Port-forwards monitoring arretes." || true

if kubectl --context "$CTX" config get-contexts "$CTX" >/dev/null 2>&1; then
  if helm --kube-context "$CTX" status "$RELEASE" -n "$NS" >/dev/null 2>&1; then
    helm --kube-context "$CTX" uninstall "$RELEASE" -n "$NS"
    echo "Release '${RELEASE}' supprimee."
  else
    echo "Release '${RELEASE}' deja absente."
  fi

  if [ "$KEEP_NS" != "--keep-ns" ]; then
    kubectl --context "$CTX" delete -k overlays/local-monitoring --ignore-not-found >/dev/null 2>&1 || true
    echo "Namespace '${NS}' supprime."
  fi
else
  echo "Contexte '${CTX}' absent."
fi
