#!/usr/bin/env bash
# =============================================================================
# local-services-up.sh — Ajoute les services restants (Airflow + MLflow + ml-api)
# sur le cluster Kind local.
#
# Prerequis : ./scripts/local-up.sh deja execute (cluster + app dev).
# Cf. rncp_soutenance/PLAN_SERVICES_RESTANTS_KIND.md.
#
# Usage :
#   ./scripts/local-services-up.sh
#   SKIP_FORWARD=1 ./scripts/local-services-up.sh
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."
INFRA_DIR="$PWD"
APP_DIR="$(cd ../crypto-bot-app 2>/dev/null && pwd || true)"

CLUSTER="${CLUSTER:-crypto-bot}"
CTX="kind-${CLUSTER}"
NS="${NS:-dev}"

# Images compose -> tags locaux utilises par overlays/local-services
SRC_AIRFLOW="crypto-bot-app-airflow-webserver:latest"
SRC_ML="crypto-bot-app-crypto-bot-ml-api:latest"
DST_AIRFLOW="airflow:local"
DST_ML="ml:local"

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
if ! kubectl --context "$CTX" -n "$NS" get deploy crypto-bot-backend >/dev/null 2>&1; then
  echo "ERREUR : l'app dev n'est pas deployee. Lancez d'abord ./scripts/local-up.sh" >&2
  exit 1
fi

info "1/5  Build des images Airflow et ML (cache compose)"
( cd "$APP_DIR" \
  && docker compose --env-file versions.env --env-file .env \
       build airflow-webserver crypto-bot-ml-api mlflow-ui )

info "2/5  Tag local + chargement dans Kind"
docker tag "$SRC_AIRFLOW" "$DST_AIRFLOW"
docker tag "$SRC_ML" "$DST_ML"
kind load docker-image --name "$CLUSTER" "$DST_AIRFLOW"
kind load docker-image --name "$CLUSTER" "$DST_ML"
ok "$DST_AIRFLOW  <- $SRC_AIRFLOW"
ok "$DST_ML       <- $SRC_ML"

info "3/5  Application des manifests (overlays/local-services)"
kubectl --context "$CTX" apply -k overlays/local-services

info "4/5  Attente (bases, migrations Airflow, puis services)"
kubectl --context "$CTX" -n "$NS" wait --for=condition=complete job/db-init      --timeout=180s
kubectl --context "$CTX" -n "$NS" wait --for=condition=complete job/airflow-init --timeout=360s
kubectl --context "$CTX" -n "$NS" rollout status deployment/airflow-webserver    --timeout=300s
kubectl --context "$CTX" -n "$NS" rollout status deployment/airflow-scheduler    --timeout=300s
kubectl --context "$CTX" -n "$NS" rollout status deployment/crypto-bot-ml-api    --timeout=300s
kubectl --context "$CTX" -n "$NS" rollout status deployment/mlflow-ui            --timeout=300s
ok "services restants prets"

echo
kubectl --context "$CTX" -n "$NS" get pods

info "5/5  Port-forward (Ctrl+C pour arreter)"
if [ "${SKIP_FORWARD:-0}" = "1" ]; then
  echo "  ignore (SKIP_FORWARD=1)."
  echo "  Airflow  : kubectl --context ${CTX} -n ${NS} port-forward svc/airflow-webserver 8280:8080"
  echo "  MLflow   : kubectl --context ${CTX} -n ${NS} port-forward svc/mlflow-ui 5081:5001"
  echo "  ML API   : kubectl --context ${CTX} -n ${NS} port-forward svc/crypto-bot-ml-api 8030:8010"
  exit 0
fi

pkill -f "port-forward.*-n ${NS}.*airflow-webserver" 2>/dev/null || true
pkill -f "port-forward.*-n ${NS}.*mlflow-ui" 2>/dev/null || true
pkill -f "port-forward.*-n ${NS}.*crypto-bot-ml-api" 2>/dev/null || true

cleanup() { kill $(jobs -p) 2>/dev/null || true; }
trap cleanup INT TERM

kubectl --context "$CTX" -n "$NS" port-forward svc/airflow-webserver 8280:8080 >/dev/null 2>&1 &
kubectl --context "$CTX" -n "$NS" port-forward svc/mlflow-ui 5081:5001 >/dev/null 2>&1 &
kubectl --context "$CTX" -n "$NS" port-forward svc/crypto-bot-ml-api 8030:8010 >/dev/null 2>&1 &
sleep 3

echo
echo "  Airflow  → http://localhost:8280   (admin / admin)"
echo "  MLflow   → http://localhost:5081"
echo "  ML API   → http://localhost:8030/health"
echo
echo "Ctrl+C pour arreter."
wait
