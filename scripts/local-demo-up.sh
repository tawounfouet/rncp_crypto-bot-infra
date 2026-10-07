#!/usr/bin/env bash
# =============================================================================
# local-demo-up.sh — Active le mode DEMONSTRATION de soutenance sur le Kind local.
#
# Equivalent K8s de "make demo-up" (crypto-bot-app) :
#   1. rebuild des images backend + frontend (elles embarquent le seed
#      backend/scripts/seed_demo.py et les correctifs B1/B4/B11/B14) ;
#   2. chargement des images dans Kind ;
#   3. application de overlays/local-demo (ENABLE_BACKGROUND_TASKS=0) ;
#   4. seed de la base (backend/scripts/seed_demo.py --reset).
#
# Prerequis : ./scripts/local-up.sh deja execute.
# Cf. crypto-bot-app/DEMO_SOUTENANCE.md.
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."
APP_DIR="$(cd ../crypto-bot-app 2>/dev/null && pwd || true)"

CLUSTER="${CLUSTER:-crypto-bot}"
CTX="kind-${CLUSTER}"
NS="${NS:-dev}"
COMPOSE_PROJECT="$(basename "${APP_DIR:-crypto-bot-app}")"

info() { printf '\n\033[36m>>> %s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }

for bin in docker kind kubectl; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERREUR : '$bin' introuvable." >&2; exit 1; }
done
[ -n "$APP_DIR" ] && [ -d "$APP_DIR" ] || { echo "ERREUR : crypto-bot-app introuvable." >&2; exit 1; }
if ! kubectl --context "$CTX" cluster-info >/dev/null 2>&1; then
  echo "ERREUR : contexte '${CTX}' injoignable. Lancez d'abord ./scripts/local-up.sh" >&2
  exit 1
fi

info "1/5  Rebuild des images backend + frontend (code demo + seed)"
( cd "$APP_DIR" \
  && make generate-requirements >/dev/null \
  && docker compose --env-file versions.env --env-file .env build crypto-bot-backend crypto-bot-frontend )
docker tag "${COMPOSE_PROJECT}-crypto-bot-backend:latest"  crypto-bot-backend:local
docker tag "${COMPOSE_PROJECT}-crypto-bot-frontend:latest" crypto-bot-frontend:local
ok "images reconstruites et taguees"

info "2/5  Chargement dans Kind"
kind load docker-image --name "$CLUSTER" crypto-bot-backend:local
kind load docker-image --name "$CLUSTER" crypto-bot-frontend:local
ok "images chargees"

info "3/5  Cles testnet (optionnel) + application de overlays/local-demo (worker de bots OFF)"
# Injecte les cles testnet depuis crypto-bot-app/.env dans un Secret K8s NON COMMITE.
# Si absentes, le seed utilise des cles factices (demo hors-ligne).
ENV_FILE="$APP_DIR/.env"
read_env_file() { [ -f "$ENV_FILE" ] && sed -n "s/^$1=//p" "$ENV_FILE" | head -1 | tr -d '\r' || true; }
BN_KEY="$(read_env_file BINANCE_API_KEY_TEST)"
BN_SECRET="$(read_env_file BINANCE_API_SECRET_TEST)"
if [ -n "$BN_KEY" ] && [ -n "$BN_SECRET" ]; then
  kubectl --context "$CTX" -n "$NS" create secret generic binance-demo-creds \
    --from-literal=BINANCE_API_KEY_TEST="$BN_KEY" \
    --from-literal=BINANCE_API_SECRET_TEST="$BN_SECRET" \
    --dry-run=client -o yaml | kubectl --context "$CTX" apply -f - >/dev/null
  ok "cles testnet injectees (secret binance-demo-creds, non commite)"
else
  echo "  pas de BINANCE_API_KEY_TEST/SECRET dans .env -> cles factices (demo hors-ligne)"
fi
kubectl --context "$CTX" apply -k overlays/local-demo

info "4/5  Redemarrage backend + frontend (prise en compte des nouvelles images)"
kubectl --context "$CTX" -n "$NS" rollout restart deployment/crypto-bot-backend
kubectl --context "$CTX" -n "$NS" rollout restart deployment/crypto-bot-frontend
kubectl --context "$CTX" -n "$NS" rollout status deployment/crypto-bot-backend  --timeout=240s
kubectl --context "$CTX" -n "$NS" rollout status deployment/crypto-bot-frontend --timeout=180s

info "5/5  Seed des donnees de demonstration (seed_demo.py --reset)"
kubectl --context "$CTX" -n "$NS" exec deploy/crypto-bot-backend -- \
  python /app/scripts/seed_demo.py --reset

echo
kubectl --context "$CTX" -n "$NS" exec postgres-0 -- psql -U postgres -d crypto_bot_db -tAc \
  "SELECT 'users='||count(*) FROM users; SELECT 'bots='||count(*) FROM user_bot_instances; SELECT 'market_data='||count(*) FROM market_data;"
echo
echo "  Frontend (Streamlit) : ./scripts/port-forward.sh dev ${CTX}  ->  http://localhost:8511"
echo "  Comptes demo :"
echo "    utilisateur : demo@cryptobot.dev  / Demo12345!"
echo "    admin       : admin@cryptobot.dev / Admin12345!"
