#!/usr/bin/env bash
# =============================================================================
# local-dashboard-official-down.sh — Retire le Kubernetes Dashboard officiel.
#
# Usage : ./scripts/local-dashboard-official-down.sh
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

CLUSTER="${CLUSTER:-crypto-bot}"
CTX="kind-${CLUSTER}"
NS="kubernetes-dashboard"

pkill -f "port-forward.*-n ${NS}.*svc/kubernetes-dashboard" 2>/dev/null && echo "Port-forward Dashboard arrete." || true

if ! kubectl --context "$CTX" config get-contexts "$CTX" >/dev/null 2>&1; then
  echo "Contexte '${CTX}' absent."
  exit 0
fi

kubectl --context "$CTX" delete namespace "$NS" --ignore-not-found
# Le manifeste upstream et notre overlay creent des ressources cluster-scoped
# (ClusterRole/ClusterRoleBinding) que la suppression du namespace ne retire pas.
kubectl --context "$CTX" delete clusterrolebinding admin-user kubernetes-dashboard --ignore-not-found
kubectl --context "$CTX" delete clusterrole kubernetes-dashboard --ignore-not-found
echo "Dashboard officiel retire."
