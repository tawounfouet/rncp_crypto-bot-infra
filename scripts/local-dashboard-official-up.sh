#!/usr/bin/env bash
# =============================================================================
# local-dashboard-official-up.sh — Deploie le Kubernetes Dashboard OFFICIEL
# (kubernetes/dashboard v2.7.0) sur le cluster Kind local.
#
# Login par token (compte admin-user, cluster-admin). Cf.
# rncp_soutenance/INVENTAIRE_ACCES_LOCAL.md.
#
# Usage : ./scripts/local-dashboard-official-up.sh
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

CLUSTER="${CLUSTER:-crypto-bot}"
CTX="kind-${CLUSTER}"
NS="kubernetes-dashboard"
DASHBOARD_VERSION="${DASHBOARD_VERSION:-v2.7.0}"
PORT="${PORT:-8443}"
MANIFEST="https://raw.githubusercontent.com/kubernetes/dashboard/${DASHBOARD_VERSION}/aio/deploy/recommended.yaml"

info() { printf '\n\033[36m>>> %s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }

for bin in docker kind kubectl; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERREUR : '$bin' introuvable." >&2; exit 1; }
done
if ! kubectl --context "$CTX" cluster-info >/dev/null 2>&1; then
  echo "ERREUR : contexte '${CTX}' injoignable. Lancez d'abord ./scripts/local-up.sh" >&2
  exit 1
fi

info "1/4  Installation du Dashboard officiel ${DASHBOARD_VERSION}"
kubectl --context "$CTX" apply -f "$MANIFEST"
ok "manifeste applique (namespace ${NS})"

info "2/4  Compte admin + token longue duree (cluster-admin)"
kubectl --context "$CTX" apply -k overlays/local-dashboard-official
# Le controleur de tokens remplit admin-user-token quelques instants apres.
for _ in $(seq 1 20); do
  [ -n "$(kubectl --context "$CTX" -n "$NS" get secret admin-user-token -o jsonpath='{.data.token}' 2>/dev/null)" ] && break
  sleep 1
done
ok "ServiceAccount admin-user + ClusterRoleBinding + secret admin-user-token"

info "3/4  Attente du Dashboard"
kubectl --context "$CTX" -n "$NS" rollout status deployment/kubernetes-dashboard --timeout=180s
kubectl --context "$CTX" -n "$NS" get pods,svc

info "4/4  Port-forward (Ctrl+C pour arreter)"
echo
echo "  URL  : https://localhost:${PORT}  (certificat auto-signe -> accepter l'avertissement)"
echo "  Login > Jeton : coller le token longue duree, copie directe dans le presse-papier :"
echo "    kubectl --context ${CTX} -n ${NS} get secret admin-user-token -o jsonpath='{.data.token}' | base64 -d | pbcopy"
echo "  (le token s'affiche aussi avec : kubectl --context ${CTX} -n ${NS} get secret admin-user-token -o jsonpath='{.data.token}' | base64 -d; echo)"
echo

if [ "${SKIP_FORWARD:-0}" = "1" ]; then
  echo "  (port-forward ignore : SKIP_FORWARD=1)"
  exit 0
fi

pkill -f "port-forward.*-n ${NS}.*svc/kubernetes-dashboard" 2>/dev/null || true

cleanup() { kill $(jobs -p) 2>/dev/null || true; }
trap cleanup INT TERM

kubectl --context "$CTX" -n "$NS" port-forward svc/kubernetes-dashboard "${PORT}:443" >/dev/null 2>&1 &
echo "  Dashboard officiel → https://localhost:${PORT}"
echo
echo "Ctrl+C pour arreter."
wait
