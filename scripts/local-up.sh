#!/usr/bin/env bash
# =============================================================================
# local-up.sh — Deploie l'infra sur un cluster Kubernetes local (Kind)
#
# Alternative a Docker Compose pour les 4 services socles
# (PostgreSQL, MinIO, Backend FastAPI, Frontend Streamlit).
#
# Usage :
#   ./scripts/local-up.sh              # cree le cluster, build, charge, deploie, port-forward
#   CLUSTER=autre ./scripts/local-up.sh
#   SKIP_FORWARD=1 ./scripts/local-up.sh   # ne pas lancer les port-forwards a la fin
#
# Voir rncp_soutenance/REMEDIATION_KIND_INFRA.md pour le contexte et les choix.
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."
INFRA_DIR="$PWD"
APP_DIR="$(cd ../crypto-bot-app 2>/dev/null && pwd || true)"

CLUSTER="${CLUSTER:-crypto-bot}"
CTX="kind-${CLUSTER}"
NS="${NS:-dev}"

ok()  { printf '  \033[32m✓\033[0m %s\n' "$1"; }
info(){ printf '\n\033[36m>>> %s\033[0m\n' "$1"; }

# --- 0. Prerequis -----------------------------------------------------------
for bin in docker kind kubectl; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERREUR : '$bin' introuvable dans le PATH." >&2; exit 1; }
done
[ -n "$APP_DIR" ] && [ -d "$APP_DIR" ] || { echo "ERREUR : crypto-bot-app introuvable (attendu : ../crypto-bot-app)." >&2; exit 1; }

# versions.env n'est PAS du shell valide (ex: AIRFLOW_SQLALCHEMY_SPEC=>=1.4.28,<2.0
# provoquerait une redirection "<2.0"). On extrait uniquement les cles utiles sans eval.
read_env() {
  sed -n "s/^$1=//p" "$APP_DIR/versions.env" | head -1
}
MINIO_IMAGE="$(read_env MINIO_IMAGE)"
MINIO_MC_IMAGE="$(read_env MINIO_MC_IMAGE)"
POSTGRES_IMAGE="$(read_env POSTGRES_IMAGE)"
PYTHON_VERSION="$(read_env PYTHON_VERSION)"
export MINIO_IMAGE MINIO_MC_IMAGE POSTGRES_IMAGE PYTHON_VERSION

: "${MINIO_IMAGE:?MINIO_IMAGE absent de versions.env}"
: "${MINIO_MC_IMAGE:?MINIO_MC_IMAGE absent de versions.env}"
POSTGRES_LOCAL_IMAGE="${POSTGRES_IMAGE:-postgres:14}"
ADMINER_LOCAL_IMAGE="${ADMINER_LOCAL_IMAGE:-adminer:4.8.1}"
COMPOSE_PROJECT="$(basename "$APP_DIR")"
# Fichiers d'environnement pour docker compose (versions.env n'est pas auto-charge).
COMPOSE_ENV_FILES=(--env-file "$APP_DIR/versions.env" --env-file "$APP_DIR/.env")

info "1/6  Cluster Kind '${CLUSTER}'"
if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  kind create cluster --name "$CLUSTER"
else
  echo "  cluster deja present, reutilisation."
fi
ok "contexte kubectl : ${CTX}"

info "2/6  Build des images applicatives (crypto-bot-backend / frontend)"
( cd "$APP_DIR" && make generate-requirements >/dev/null && docker compose "${COMPOSE_ENV_FILES[@]}" build crypto-bot-backend crypto-bot-frontend )
docker tag "${COMPOSE_PROJECT}-crypto-bot-backend:latest"  crypto-bot-backend:local
docker tag "${COMPOSE_PROJECT}-crypto-bot-frontend:latest" crypto-bot-frontend:local
ok "images taguees crypto-bot-backend:local / crypto-bot-frontend:local"

info "3/6  Chargement des images dans Kind"
# Les images tierces sont tirees en local puis chargees (aucun pull cote node).
docker pull "$MINIO_IMAGE"
docker pull "$MINIO_MC_IMAGE"
docker pull "$POSTGRES_LOCAL_IMAGE"
docker pull "$ADMINER_LOCAL_IMAGE"
for img in "crypto-bot-backend:local" "crypto-bot-frontend:local" \
           "$MINIO_IMAGE" "$MINIO_MC_IMAGE" "$POSTGRES_LOCAL_IMAGE" "$ADMINER_LOCAL_IMAGE"; do
  kind load docker-image --name "$CLUSTER" "$img"
  ok "charge : $img"
done

info "4/6  Application des manifests (overlays/local)"
kubectl --context "$CTX" apply -k overlays/local

info "5/6  Attente de la disponibilite des services"
kubectl --context "$CTX" -n "$NS" rollout status statefulset/postgres            --timeout=180s
kubectl --context "$CTX" -n "$NS" rollout status statefulset/minio               --timeout=180s
kubectl --context "$CTX" -n "$NS" rollout status deployment/crypto-bot-backend   --timeout=240s
kubectl --context "$CTX" -n "$NS" rollout status deployment/crypto-bot-frontend  --timeout=180s
kubectl --context "$CTX" -n "$NS" rollout status deployment/adminer              --timeout=120s
kubectl --context "$CTX" -n "$NS" wait --for=condition=complete job/minio-createbuckets --timeout=120s
ok "tous les services sont prets"

echo
kubectl --context "$CTX" -n "$NS" get pods,pvc

info "6/6  Port-forward (Ctrl+C pour arreter)"
if [ "${SKIP_FORWARD:-0}" = "1" ]; then
  echo "  ignore (SKIP_FORWARD=1). Lancez : ./scripts/port-forward.sh ${NS} ${CTX}"
else
  exec ./scripts/port-forward.sh "$NS" "$CTX"
fi
