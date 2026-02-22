#!/usr/bin/env bash
#
# Lance tous les port-forwards pour un namespace donne.
# Chaque environnement utilise des ports locaux differents pour eviter les conflits.
#
# Usage: ./port-forward.sh [dev|staging|production]
#
# Ports locaux :
#   dev        → 8009/8501/5432/27017/9000/9001
#   staging    → 8109/8601/5532/27117/9100/9101
#   production → 8209/8701/5632/27217/9200/9201
#
set -euo pipefail

NS="${1:-dev}"
CTX="admin@crypto-bot"

# Validation du namespace
case "$NS" in
  dev|staging|production) ;;
  *) echo "Usage: $0 [dev|staging|production]"; exit 1 ;;
esac

# Ports par environnement (local:remote)
case "$NS" in
  dev)
    P_BACKEND=8009;  P_FRONTEND=8501
    P_PG=5432;       P_MONGO=27017
    P_MINIO=9000;    P_MINIOC=9001
    ;;
  staging)
    P_BACKEND=8109;  P_FRONTEND=8601
    P_PG=5532;       P_MONGO=27117
    P_MINIO=9100;    P_MINIOC=9101
    ;;
  production)
    P_BACKEND=8209;  P_FRONTEND=8701
    P_PG=5632;       P_MONGO=27217
    P_MINIO=9200;    P_MINIOC=9201
    ;;
esac

# Tue les port-forwards existants au Ctrl+C
cleanup() {
  echo ""
  echo "Arret des port-forwards..."
  kill $(jobs -p) 2>/dev/null
  exit 0
}
trap cleanup INT TERM

echo "=== Port-forward namespace: $NS ==="
echo ""

kubectl --context "$CTX" port-forward -n "$NS" svc/crypto-bot-backend  ${P_BACKEND}:8009 &
echo "  Backend API      → http://localhost:${P_BACKEND}/api/v1/docs"

kubectl --context "$CTX" port-forward -n "$NS" svc/crypto-bot-frontend ${P_FRONTEND}:8501 &
echo "  Frontend         → http://localhost:${P_FRONTEND}"

kubectl --context "$CTX" port-forward -n "$NS" svc/postgres            ${P_PG}:5432 &
echo "  PostgreSQL       → localhost:${P_PG}"

kubectl --context "$CTX" port-forward -n "$NS" svc/mongo               ${P_MONGO}:27017 &
echo "  MongoDB          → localhost:${P_MONGO}"

kubectl --context "$CTX" port-forward -n "$NS" svc/minio               ${P_MINIO}:9000 ${P_MINIOC}:9001 &
echo "  MinIO API        → localhost:${P_MINIO}"
echo "  MinIO Console    → http://localhost:${P_MINIOC}"

echo ""
echo "Ctrl+C pour tout arreter."
echo ""

wait
