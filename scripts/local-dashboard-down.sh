#!/usr/bin/env bash
# =============================================================================
# local-dashboard-down.sh — Retire Headlamp (UI Kubernetes) du cluster Kind local.
#
# Usage : ./scripts/local-dashboard-down.sh
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

CLUSTER="${CLUSTER:-crypto-bot}"
CTX="kind-${CLUSTER}"
NS="headlamp"
RELEASE="${RELEASE:-headlamp}"

pkill -f "port-forward.*-n ${NS}.*svc/headlamp" 2>/dev/null && echo "Port-forward Headlamp arrete." || true

if ! kubectl --context "$CTX" config get-contexts "$CTX" >/dev/null 2>&1; then
  echo "Contexte '${CTX}' absent."
  exit 0
fi

if helm --kube-context "$CTX" status "$RELEASE" -n "$NS" >/dev/null 2>&1; then
  helm --kube-context "$CTX" uninstall "$RELEASE" -n "$NS"
  echo "Release '${RELEASE}' supprimee (ClusterRoleBinding inclus)."
else
  echo "Release '${RELEASE}' deja absente."
fi

kubectl --context "$CTX" delete namespace "$NS" --ignore-not-found >/dev/null 2>&1 || true
echo "Namespace '${NS}' supprime."
