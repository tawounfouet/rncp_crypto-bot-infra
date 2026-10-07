#!/usr/bin/env bash
#
# Lance tous les port-forwards pour un namespace donne.
# Chaque environnement utilise des ports locaux differents pour eviter les conflits.
#
# Usage: ./port-forward.sh [dev|staging|production|infra|dashboard|all] [contexte-kubectl]
#
# Ports locaux :
#   dev        → 8019/8511/5442/9020/9021 (+ adminer 8085, airflow 8280, mlflow 5081, ml-api 8030)
#   staging    → 8109/8601/5532/9100/9101
#   production → 8209/8701/5632/9200/9201
#   infra      → 8443 (ArgoCD) / 3000 (Grafana)
#   dashboard  → 8090 (Headlamp, UI Kubernetes)
#   all        → staging + infra
#
# Le pool dev est volontairement distinct de docker-compose.yml (dev local :
# 8009/8501/5434/9000/9001) : les deux peuvent tourner en parallele sur le
# meme poste sans se percuter. Adminer dev = 8085 (idem compose, non re-mappe).
#
set -euo pipefail

NS="${1:-dev}"
# Contexte par defaut = cluster distant. En local (Kind) : ./port-forward.sh dev kind-crypto-bot
CTX="${2:-admin@crypto-bot}"

# Validation du namespace
case "$NS" in
  dev|staging|production|infra|dashboard|all) ;;
  *) echo "Usage: $0 [dev|staging|production|infra|dashboard|all] [contexte-kubectl]"; exit 1 ;;
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

# --- Fonction : port-forward UI Kubernetes (Headlamp) ---
forward_dashboard() {
  echo "=== Port-forward UI Kubernetes (Headlamp) ==="
  echo ""

  kubectl --context "$CTX" port-forward -n headlamp svc/headlamp 8090:80 &
  echo "  Headlamp         → http://localhost:8090"

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
      P_ADMINER=8085
      P_AIRFLOW=8280;  P_MLFLOW=5081;  P_MLAPI=8030
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

  # Adminer : outil de dev local uniquement (absent de base/, donc de staging/production).
  if [ -n "${P_ADMINER:-}" ]; then
    kubectl --context "$CTX" port-forward -n "$ns" svc/adminer ${P_ADMINER}:8080 &
    echo "  Adminer (Postgres) → http://localhost:${P_ADMINER}"
  fi

  # Services restants (Airflow / MLflow / ml-api) -- presents seulement si
  # overlays/local-services a ete applique.
  if [ -n "${P_AIRFLOW:-}" ] && kubectl --context "$CTX" get svc/airflow-webserver -n "$ns" >/dev/null 2>&1; then
    kubectl --context "$CTX" port-forward -n "$ns" svc/airflow-webserver ${P_AIRFLOW}:8080 &
    echo "  Airflow          → http://localhost:${P_AIRFLOW}"
  fi
  if [ -n "${P_MLFLOW:-}" ] && kubectl --context "$CTX" get svc/mlflow-ui -n "$ns" >/dev/null 2>&1; then
    kubectl --context "$CTX" port-forward -n "$ns" svc/mlflow-ui ${P_MLFLOW}:5001 &
    echo "  MLflow           → http://localhost:${P_MLFLOW}"
  fi
  if [ -n "${P_MLAPI:-}" ] && kubectl --context "$CTX" get svc/crypto-bot-ml-api -n "$ns" >/dev/null 2>&1; then
    kubectl --context "$CTX" port-forward -n "$ns" svc/crypto-bot-ml-api ${P_MLAPI}:8010 &
    echo "  ML API           → http://localhost:${P_MLAPI}/health"
  fi

  echo ""
}

# --- Lancement ---
case "$NS" in
  infra)
    forward_infra
    ;;
  dashboard)
    forward_dashboard
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
