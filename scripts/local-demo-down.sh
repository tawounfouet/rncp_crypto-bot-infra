#!/usr/bin/env bash
# =============================================================================
# local-demo-down.sh — Quitte le mode DEMONSTRATION (reactive le worker de bots).
#
# Usage : ./scripts/local-demo-down.sh
# Les donnees seedees restent en base (utiliser local-down.sh --purge pour tout effacer).
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

CLUSTER="${CLUSTER:-crypto-bot}"
CTX="kind-${CLUSTER}"
NS="${NS:-dev}"

if ! kubectl --context "$CTX" config get-contexts "$CTX" >/dev/null 2>&1; then
  echo "Contexte '${CTX}' absent."
  exit 0
fi

# Re-applique l'overlay normal (sans ENABLE_BACKGROUND_TASKS=0) puis redemarre.
kubectl --context "$CTX" apply -k overlays/local
kubectl --context "$CTX" -n "$NS" delete secret binance-demo-creds --ignore-not-found >/dev/null 2>&1 || true
kubectl --context "$CTX" -n "$NS" rollout restart deployment/crypto-bot-backend
kubectl --context "$CTX" -n "$NS" rollout status deployment/crypto-bot-backend --timeout=240s
echo "Mode demo desactive (worker de bots reactive, secret testnet supprime). Donnees conservees."
