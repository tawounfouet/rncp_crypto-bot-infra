#!/usr/bin/env bash
set -euo pipefail

# Rotation des secrets applicatifs (crypto-bot-secrets) pour un environnement.
#
# Regenere POSTGRES_PWD, MINIO_ACCESS_KEY, MINIO_SECRET_KEY, SECRET_KEY et
# BINANCE_ENC_KEY, applique le nouveau mot de passe directement dans
# PostgreSQL, re-scelle le secret avec kubeseal, l'applique au cluster puis
# redemarre minio et le backend pour qu'ils prennent les nouvelles valeurs.
#
# BINANCE_ENC_KEY chiffre les cles API Binance stockees en base
# (user_settings.api_keys). Ce script ne doit etre lance QUE si aucune cle
# n'est actuellement stockee (verifie au prealable), sinon elle deviendrait
# illisible. POSTGRES_USER n'est pas rote (identifiant, pas un secret).
#
# Usage : ./rotate_secrets.sh <staging|production>

usage() {
  echo "Usage: $0 <staging|production>" >&2
  exit 1
}

[[ $# -eq 1 ]] || usage
ENV="$1"

case "$ENV" in
  staging|production) NAMESPACE="$ENV" ;;
  *) usage ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_FILE="$REPO_ROOT/overlays/$ENV/secrets.yaml"

[[ -f "$SECRETS_FILE" ]] || { echo "Introuvable: $SECRETS_FILE" >&2; exit 1; }

for bin in kubectl kubeseal openssl; do
  command -v "$bin" >/dev/null 2>&1 || { echo "Manquant: $bin" >&2; exit 1; }
done

echo "==> Rotation des secrets pour l'environnement: $ENV (namespace: $NAMESPACE)"
read -rp "Confirmer ? (oui/non) " CONFIRM
[[ "$CONFIRM" == "oui" ]] || { echo "Annule."; exit 0; }

gen_secret() {
  # Chaine alphanumerique aleatoire (longueur donnee en argument)
  local length="${1:-32}"
  openssl rand -base64 64 | tr -dc 'A-Za-z0-9' | head -c "$length"
}

gen_binance_key() {
  # Cle AES 32 octets encodee en base64, format attendu par security.py
  openssl rand -base64 32
}

echo "==> Generation des nouvelles valeurs"
NEW_POSTGRES_PWD="$(gen_secret 32)"
NEW_MINIO_ACCESS_KEY="$(gen_secret 20)"
NEW_MINIO_SECRET_KEY="$(gen_secret 40)"
NEW_SECRET_KEY="$(gen_secret 50)"
NEW_BINANCE_ENC_KEY="$(gen_binance_key)"

echo "==> Lecture de l'utilisateur PostgreSQL actuel"
POSTGRES_USER="$(kubectl exec -n "$NAMESPACE" postgres-0 -- printenv POSTGRES_USER)"

echo "==> Mise a jour du mot de passe PostgreSQL en direct (ALTER USER)"
# Connexion via socket local dans le pod : authentification "trust" par
# defaut sur l'image postgres officielle, pas besoin du mot de passe actuel.
kubectl exec -n "$NAMESPACE" postgres-0 -- \
  psql -U "$POSTGRES_USER" -d postgres -c \
  "ALTER USER \"$POSTGRES_USER\" WITH PASSWORD '$NEW_POSTGRES_PWD';"

echo "==> Construction du Secret Kubernetes en clair (fichier temporaire, jamais commite)"
TMP_SECRET="$(mktemp)"
trap 'rm -f "$TMP_SECRET"' EXIT

cat > "$TMP_SECRET" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: crypto-bot-secrets
  namespace: $NAMESPACE
type: Opaque
stringData:
  POSTGRES_USER: "$POSTGRES_USER"
  POSTGRES_PWD: "$NEW_POSTGRES_PWD"
  MINIO_ACCESS_KEY: "$NEW_MINIO_ACCESS_KEY"
  MINIO_SECRET_KEY: "$NEW_MINIO_SECRET_KEY"
  SECRET_KEY: "$NEW_SECRET_KEY"
  BINANCE_ENC_KEY: "$NEW_BINANCE_ENC_KEY"
EOF

echo "==> Chiffrement avec kubeseal"
kubeseal --controller-namespace kube-system --format yaml < "$TMP_SECRET" > "$SECRETS_FILE"

echo "==> Application immediate du secret au cluster"
kubectl apply -f "$SECRETS_FILE"

echo "==> Redemarrage de MinIO (les credentials root sont relues au demarrage)"
kubectl rollout restart statefulset/minio -n "$NAMESPACE"
kubectl rollout status statefulset/minio -n "$NAMESPACE" --timeout=120s

echo "==> Redemarrage du backend (prend POSTGRES_PWD / SECRET_KEY / BINANCE_ENC_KEY a jour)"
kubectl rollout restart deployment/crypto-bot-backend -n "$NAMESPACE"
kubectl rollout status deployment/crypto-bot-backend -n "$NAMESPACE" --timeout=120s

echo
echo "==> Verification post-rotation"
CHECK_OK=1

# --field-selector=status.phase=Running + tri par date de creation : pendant
# la bascule, l'ancien pod (Completed/Terminating) est encore liste par
# 'kubectl get', il ne faut pas lire ses logs par erreur.
BACKEND_POD="$(kubectl get pods -n "$NAMESPACE" -l app=crypto-bot-backend \
  --field-selector=status.phase=Running --sort-by=.metadata.creationTimestamp \
  -o name | tail -1 | cut -d/ -f2)"
MINIO_POD="$(kubectl get pods -n "$NAMESPACE" -l app=minio \
  --field-selector=status.phase=Running --sort-by=.metadata.creationTimestamp \
  -o name | tail -1 | cut -d/ -f2)"

echo "--- Etat des pods ---"
kubectl get pods -n "$NAMESPACE" -l app=crypto-bot-backend
kubectl get pods -n "$NAMESPACE" -l app=minio

echo "--- Logs backend ($BACKEND_POD) ---"
BACKEND_LOGS="$(kubectl logs -n "$NAMESPACE" "$BACKEND_POD" --tail=200)"

if echo "$BACKEND_LOGS" | grep -q "Application startup completed successfully"; then
  echo "  [OK] demarrage backend confirme dans les logs"
else
  echo "  [ECHEC] pas de confirmation de demarrage dans les logs backend"
  CHECK_OK=0
fi

if echo "$BACKEND_LOGS" | grep -qE 'GET /health HTTP/1\.1" 200'; then
  echo "  [OK] readiness/liveness probe /health repond 200"
else
  echo "  [ECHEC] aucun /health 200 OK vu dans les logs recents"
  CHECK_OK=0
fi

if echo "$BACKEND_LOGS" | grep -qiE 'error|traceback|failed'; then
  echo "  [ATTENTION] lignes suspectes dans les logs backend, a verifier manuellement :"
  echo "$BACKEND_LOGS" | grep -iE 'error|traceback|failed' | sed 's/^/      /'
fi

echo "--- Logs MinIO ($MINIO_POD) ---"
MINIO_LOGS="$(kubectl logs -n "$NAMESPACE" "$MINIO_POD" --tail=50)"

if echo "$MINIO_LOGS" | grep -q "WebUI:"; then
  echo "  [OK] MinIO demarre proprement"
else
  echo "  [ECHEC] MinIO ne semble pas avoir demarre correctement"
  CHECK_OK=0
fi

if echo "$MINIO_LOGS" | grep -qiE 'error|fatal'; then
  echo "  [ATTENTION] lignes suspectes dans les logs MinIO, a verifier manuellement :"
  echo "$MINIO_LOGS" | grep -iE 'error|fatal' | sed 's/^/      /'
fi

echo
if [[ "$CHECK_OK" -eq 1 ]]; then
  echo "==> Verification OK. Tu peux commiter $SECRETS_FILE dans Git (contenu chiffre, safe pour le repo)."
else
  echo "==> Verification ECHOUEE. Ne pas commiter tel quel : investigue avant de continuer." >&2
  exit 1
fi
