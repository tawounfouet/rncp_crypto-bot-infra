#!/usr/bin/env bash
#
# Lance tous les port-forwards pour un namespace donne.
# Usage: ./port-forward.sh [dev|staging|production]
#
set -euo pipefail

NS="${1:-dev}"
CTX="admin@crypto-bot"

# Validation du namespace
case "$NS" in
  dev|staging|production) ;;
  *) echo "Usage: $0 [dev|staging|production]"; exit 1 ;;
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

kubectl --context "$CTX" port-forward -n "$NS" svc/crypto-bot-backend 8009:8009 &
echo "  Backend API      → http://localhost:8009/api/v1/docs"

kubectl --context "$CTX" port-forward -n "$NS" svc/crypto-bot-frontend 8501:8501 &
echo "  Frontend         → http://localhost:8501"

kubectl --context "$CTX" port-forward -n "$NS" svc/postgres 5432:5432 &
echo "  PostgreSQL       → localhost:5432"

kubectl --context "$CTX" port-forward -n "$NS" svc/mongo 27017:27017 &
echo "  MongoDB          → localhost:27017"

kubectl --context "$CTX" port-forward -n "$NS" svc/minio 9000:9000 9001:9001 &
echo "  MinIO API        → localhost:9000"
echo "  MinIO Console    → http://localhost:9001"

echo ""
echo "Ctrl+C pour tout arreter."
echo ""

wait
