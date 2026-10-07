#!/usr/bin/env bash
# =============================================================================
# local-services-down.sh — Retire les services restants (Airflow + MLflow + ml-api)
# sans toucher a l'app de base (namespace dev conserve).
#
# Usage : ./scripts/local-services-down.sh
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

CLUSTER="${CLUSTER:-crypto-bot}"
CTX="kind-${CLUSTER}"
NS="${NS:-dev}"

pkill -f "port-forward.*-n ${NS}.*airflow-webserver" 2>/dev/null || true
pkill -f "port-forward.*-n ${NS}.*mlflow-ui" 2>/dev/null || true
pkill -f "port-forward.*-n ${NS}.*crypto-bot-ml-api" 2>/dev/null || true

if ! kubectl --context "$CTX" config get-contexts "$CTX" >/dev/null 2>&1; then
  echo "Contexte '${CTX}' absent."
  exit 0
fi

kubectl --context "$CTX" -n "$NS" delete job db-init airflow-init --ignore-not-found
kubectl --context "$CTX" -n "$NS" delete deployment airflow-webserver airflow-scheduler crypto-bot-ml-api mlflow-ui --ignore-not-found
kubectl --context "$CTX" -n "$NS" delete service airflow-webserver crypto-bot-ml-api mlflow-ui --ignore-not-found
kubectl --context "$CTX" -n "$NS" delete pvc models-artifacts --ignore-not-found
kubectl --context "$CTX" -n "$NS" delete secret airflow-secrets --ignore-not-found
kubectl --context "$CTX" -n "$NS" delete configmap airflow-config --ignore-not-found

echo "Services restants (Airflow/MLflow/ml-api) retires. L'app de base reste en place."
