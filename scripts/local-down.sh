#!/usr/bin/env bash
# =============================================================================
# local-down.sh — Supprime l'environnement local deploye par local-up.sh
#
# Usage :
#   ./scripts/local-down.sh            # supprime le namespace (garde le cluster)
#   ./scripts/local-down.sh --purge    # supprime aussi le cluster Kind
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

CLUSTER="${CLUSTER:-crypto-bot}"
CTX="kind-${CLUSTER}"
NS="${NS:-dev}"
PURGE="${1:-}"

# Coupe les port-forwards eventuels sur ce contexte.
pkill -f "kubectl.*port-forward.*--context.*${CTX}" 2>/dev/null && echo "Port-forwards arretes." || true

if kubectl config get-contexts "$CTX" >/dev/null 2>&1; then
  if kubectl --context "$CTX" get namespace "$NS" >/dev/null 2>&1; then
    kubectl --context "$CTX" delete namespace "$NS" --wait=true
    echo "Namespace '${NS}' supprime."
  else
    echo "Namespace '${NS}' deja absent."
  fi
else
  echo "Contexte '${CTX}' absent (cluster deja supprime ?)."
fi

if [ "$PURGE" = "--purge" ]; then
  kind delete cluster --name "$CLUSTER"
  echo "Cluster Kind '${CLUSTER}' supprime."
fi
