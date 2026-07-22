#!/usr/bin/env bash
#
# Lance tous les port-forwards pour un namespace donne.
# Chaque environnement utilise des ports locaux differents pour eviter les conflits.
#
# Usage: ./port-forward.sh [dev|staging|production|infra|all]
#
# Ports locaux :
#   dev        → 8019/8511/5442/9020/9021
#   staging    → 8109/8601/5532/9100/9101
#   production → 8209/8701/5632/9200/9201
#   infra      → 8443 (ArgoCD) / 3000 (Grafana)
#   all        → staging + infra
#
# Le pool dev est volontairement distinct de docker-compose.yml (dev local :
# 8009/8501/5434/9000/9001) : les deux peuvent tourner en parallele sur le
# meme poste sans se percuter.
#
set -euo pipefail

NS="${1:-dev}"
CTX="admin@crypto-bot"

# Validation du namespace
case "$NS" in
  dev|staging|production|infra|all) ;;
  *) echo "Usage: $0 [dev|staging|production|infra|all]"; exit 1 ;;
esac

# Tue les anciens port-forwards kubectl (evite les conflits de ports)
pkill -f "kubectl.*port-forward.*--context.*$CTX" 2>/dev/null && sleep 1 && echo "Anciens port-forwards tues." || true

# Tue les port-forwards existants au Ctrl+C
cleanup() {
  echo ""
  echo "Arret des port-forwards..."
  kill $(jobs -p) 2>/dev/null
  exit 0
}
trap cleanup INT TERM

# --- Fonction : port-forward infra (ArgoCD + Grafana) ---
forward_infra() {
  echo "=== Port-forward infra ==="
  echo ""

  kubectl --context "$CTX" port-forward -n argocd svc/argocd-server 8443:443 &
  echo "  ArgoCD           → https://localhost:8443"

  kubectl --context "$CTX" port-forward -n monitoring svc/monitoring-grafana 3000:80 &
  echo "  Grafana          → http://localhost:3000"

  echo ""
}

# --- Fonction : port-forward apps (backend, frontend, DBs) ---
forward_apps() {
  local ns="$1"

  # Ports par environnement (local:remote)
  case "$ns" in
    dev)
      P_BACKEND=8019;  P_FRONTEND=8511
      P_PG=5442
      P_MINIO=9020;    P_MINIOC=9021
      ;;
    staging)
      P_BACKEND=8109;  P_FRONTEND=8601
      P_PG=5532
      P_MINIO=9100;    P_MINIOC=9101
      ;;
    production)
      P_BACKEND=8209;  P_FRONTEND=8701
      P_PG=5632
      P_MINIO=9200;    P_MINIOC=9201
      ;;
  esac

  echo "=== Port-forward namespace: $ns ==="
  echo ""

  kubectl --context "$CTX" port-forward -n "$ns" svc/crypto-bot-backend  ${P_BACKEND}:8009 &
  echo "  Backend API      → http://localhost:${P_BACKEND}/api/v1/docs"

  kubectl --context "$CTX" port-forward -n "$ns" svc/crypto-bot-frontend ${P_FRONTEND}:8501 &
  echo "  Frontend         → http://localhost:${P_FRONTEND}"

  kubectl --context "$CTX" port-forward -n "$ns" svc/postgres            ${P_PG}:5432 &
  echo "  PostgreSQL       → localhost:${P_PG}"


  kubectl --context "$CTX" port-forward -n "$ns" svc/minio               ${P_MINIO}:9000 ${P_MINIOC}:9001 &
  echo "  MinIO API        → localhost:${P_MINIO}"
  echo "  MinIO Console    → http://localhost:${P_MINIOC}"

  echo ""
}

# --- Lancement ---
case "$NS" in
  infra)
    forward_infra
    ;;
  all)
    forward_infra
    forward_apps staging
    ;;
  *)
    forward_apps "$NS"
    ;;
esac

echo "Ctrl+C pour tout arreter."
echo ""

wait
