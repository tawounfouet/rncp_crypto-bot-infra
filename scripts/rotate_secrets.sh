#!/usr/bin/env bash
set -euo pipefail

# Rotation des secrets de l'infra crypto-bot.
#
# Modes :
#   staging | production  -> secrets applicatifs (crypto-bot-secrets) :
#     POSTGRES_PWD, MINIO_ACCESS_KEY, MINIO_SECRET_KEY, SECRET_KEY,
#     EXCHANGE_ENC_KEY. Applique le nouveau mot de passe directement dans
#     PostgreSQL, re-scelle le secret avec kubeseal, l'applique au cluster
#     puis redemarre minio et le backend.
#
#     EXCHANGE_ENC_KEY chiffre les cles API exchange (Binance, Kraken, ...)
#     stockees en base (user_settings.api_keys). Ce mode ne doit etre lance QUE si aucune cle
#     n'est actuellement stockee (verifie au prealable), sinon elle
#     deviendrait illisible. POSTGRES_USER n'est pas rote (identifiant, pas
#     un secret).
#
#   argocd    -> mot de passe admin ArgoCD (compte unique du cluster, pas de
#     SealedSecret : rotation via `argocd account update-password`).
#
#   grafana   -> mot de passe admin Grafana (monitoring/grafana-admin-sealed.yaml),
#     re-scelle et redemarre le pod (stockage ephemere : reinit propre a
#     chaque redemarrage).
#
# Usage : ./rotate_secrets.sh <staging|production|argocd|grafana>

usage() {
  echo "Usage: $0 <staging|production|argocd|grafana>" >&2
  exit 1
}

[[ $# -eq 1 ]] || usage
MODE="$1"

case "$MODE" in
  staging|production|argocd|grafana) ;;
  *) usage ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for bin in kubectl kubeseal openssl; do
  command -v "$bin" >/dev/null 2>&1 || { echo "Manquant: $bin" >&2; exit 1; }
done

gen_secret() {
  # Chaine alphanumerique aleatoire (longueur donnee en argument)
  local length="${1:-32}"
  openssl rand -base64 64 | tr -dc 'A-Za-z0-9' | head -c "$length"
}

gen_exchange_key() {
  # Cle AES 32 octets encodee en base64, format attendu par security.py
  openssl rand -base64 32
}

confirm() {
  read -rp "Confirmer ? (oui/non) " CONFIRM
  [[ "$CONFIRM" == "oui" ]] || { echo "Annule."; exit 0; }
}

# -----------------------------------------------------------------------
# Mode staging / production : secrets applicatifs
# -----------------------------------------------------------------------
rotate_app_secrets() {
  local namespace="$1"
  local secrets_file="$REPO_ROOT/overlays/$namespace/secrets.yaml"

  [[ -f "$secrets_file" ]] || { echo "Introuvable: $secrets_file" >&2; exit 1; }

  echo "==> Rotation des secrets applicatifs pour: $namespace"
  confirm

  echo "==> Generation des nouvelles valeurs"
  local new_postgres_pwd new_minio_access_key new_minio_secret_key new_secret_key new_exchange_enc_key
  new_postgres_pwd="$(gen_secret 32)"
  new_minio_access_key="$(gen_secret 20)"
  new_minio_secret_key="$(gen_secret 40)"
  new_secret_key="$(gen_secret 50)"
  new_exchange_enc_key="$(gen_exchange_key)"

  echo "==> Lecture de l'utilisateur PostgreSQL actuel"
  local postgres_user
  postgres_user="$(kubectl exec -n "$namespace" postgres-0 -- printenv POSTGRES_USER)"

  echo "==> Mise a jour du mot de passe PostgreSQL en direct (ALTER USER)"
  # Connexion via socket local dans le pod : authentification "trust" par
  # defaut sur l'image postgres officielle, pas besoin du mot de passe actuel.
  kubectl exec -n "$namespace" postgres-0 -- \
    psql -U "$postgres_user" -d postgres -c \
    "ALTER USER \"$postgres_user\" WITH PASSWORD '$new_postgres_pwd';"

  echo "==> Construction du Secret Kubernetes en clair (fichier temporaire, jamais commite)"
  local tmp_secret
  tmp_secret="$(mktemp)"
  trap 'rm -f "$tmp_secret"' RETURN

  cat > "$tmp_secret" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: crypto-bot-secrets
  namespace: $namespace
type: Opaque
stringData:
  POSTGRES_USER: "$postgres_user"
  POSTGRES_PWD: "$new_postgres_pwd"
  MINIO_ACCESS_KEY: "$new_minio_access_key"
  MINIO_SECRET_KEY: "$new_minio_secret_key"
  SECRET_KEY: "$new_secret_key"
  EXCHANGE_ENC_KEY: "$new_exchange_enc_key"
EOF

  echo "==> Chiffrement avec kubeseal"
  kubeseal --controller-namespace kube-system --format yaml < "$tmp_secret" > "$secrets_file"

  echo "==> Application immediate du secret au cluster"
  kubectl apply -f "$secrets_file"

  echo "==> Redemarrage de MinIO (les credentials root sont relues au demarrage)"
  kubectl rollout restart statefulset/minio -n "$namespace"
  kubectl rollout status statefulset/minio -n "$namespace" --timeout=120s

  echo "==> Redemarrage du backend (prend POSTGRES_PWD / SECRET_KEY / EXCHANGE_ENC_KEY a jour)"
  kubectl rollout restart deployment/crypto-bot-backend -n "$namespace"
  kubectl rollout status deployment/crypto-bot-backend -n "$namespace" --timeout=120s

  echo
  echo "==> Verification post-rotation"
  local check_ok=1

  # --field-selector=status.phase=Running + tri par date de creation : pendant
  # la bascule, l'ancien pod (Completed/Terminating) est encore liste par
  # 'kubectl get', il ne faut pas lire ses logs par erreur.
  local backend_pod minio_pod
  backend_pod="$(kubectl get pods -n "$namespace" -l app=crypto-bot-backend \
    --field-selector=status.phase=Running --sort-by=.metadata.creationTimestamp \
    -o name | tail -1 | cut -d/ -f2)"
  minio_pod="$(kubectl get pods -n "$namespace" -l app=minio \
    --field-selector=status.phase=Running --sort-by=.metadata.creationTimestamp \
    -o name | tail -1 | cut -d/ -f2)"

  echo "--- Etat des pods ---"
  kubectl get pods -n "$namespace" -l app=crypto-bot-backend
  kubectl get pods -n "$namespace" -l app=minio

  echo "--- Logs backend ($backend_pod) ---"
  local backend_logs
  backend_logs="$(kubectl logs -n "$namespace" "$backend_pod" --tail=200)"

  if echo "$backend_logs" | grep -q "Application startup completed successfully"; then
    echo "  [OK] demarrage backend confirme dans les logs"
  else
    echo "  [ECHEC] pas de confirmation de demarrage dans les logs backend"
    check_ok=0
  fi

  if echo "$backend_logs" | grep -qE 'GET /health HTTP/1\.1" 200'; then
    echo "  [OK] readiness/liveness probe /health repond 200"
  else
    echo "  [ECHEC] aucun /health 200 OK vu dans les logs recents"
    check_ok=0
  fi

  if echo "$backend_logs" | grep -qiE 'error|traceback|failed'; then
    echo "  [ATTENTION] lignes suspectes dans les logs backend, a verifier manuellement :"
    echo "$backend_logs" | grep -iE 'error|traceback|failed' | sed 's/^/      /'
  fi

  echo "--- Logs MinIO ($minio_pod) ---"
  local minio_logs
  minio_logs="$(kubectl logs -n "$namespace" "$minio_pod" --tail=50)"

  if echo "$minio_logs" | grep -q "WebUI:"; then
    echo "  [OK] MinIO demarre proprement"
  else
    echo "  [ECHEC] MinIO ne semble pas avoir demarre correctement"
    check_ok=0
  fi

  if echo "$minio_logs" | grep -qiE 'error|fatal'; then
    echo "  [ATTENTION] lignes suspectes dans les logs MinIO, a verifier manuellement :"
    echo "$minio_logs" | grep -iE 'error|fatal' | sed 's/^/      /'
  fi

  echo
  if [[ "$check_ok" -eq 1 ]]; then
    echo "==> Verification OK. Tu peux commiter $secrets_file dans Git (contenu chiffre, safe pour le repo)."
  else
    echo "==> Verification ECHOUEE. Ne pas commiter tel quel : investigue avant de continuer." >&2
    exit 1
  fi
}

# -----------------------------------------------------------------------
# Mode argocd : mot de passe admin (pas de SealedSecret, rotation via CLI)
# -----------------------------------------------------------------------
rotate_argocd() {
  echo "==> Rotation du mot de passe admin ArgoCD"
  confirm

  local current_pwd
  if kubectl get secret argocd-initial-admin-secret -n argocd >/dev/null 2>&1; then
    current_pwd="$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d)"
    echo "==> Mot de passe actuel recupere depuis argocd-initial-admin-secret"
  else
    echo "==> argocd-initial-admin-secret absent (deja supprime apres un precedent changement)."
    read -rsp "Mot de passe admin ArgoCD actuel : " current_pwd
    echo
  fi

  local new_pwd
  new_pwd="$(gen_secret 24)"

  echo "==> Connexion et changement de mot de passe (via le pod argocd-server)"
  # argocd-server sert en TLS sur 8080 (pas de flag "insecure" cote serveur) :
  # --insecure cote client desactive juste la verif du certificat, il ne faut
  # PAS ajouter --plaintext (qui forcerait du HTTP en clair vers un port TLS
  # et bloque la connexion silencieusement).
  kubectl exec -n argocd deployment/argocd-server -- \
    argocd login localhost:8080 --username admin --password "$current_pwd" --insecure </dev/null

  kubectl exec -n argocd deployment/argocd-server -- \
    argocd account update-password \
    --current-password "$current_pwd" --new-password "$new_pwd" \
    --server localhost:8080 --insecure </dev/null

  echo "==> Verification : connexion avec le nouveau mot de passe"
  if kubectl exec -n argocd deployment/argocd-server -- \
    argocd login localhost:8080 --username admin --password "$new_pwd" --insecure </dev/null >/dev/null 2>&1; then
    echo "  [OK] connexion reussie avec le nouveau mot de passe"
  else
    echo "  [ECHEC] la connexion avec le nouveau mot de passe a echoue" >&2
    exit 1
  fi

  if kubectl get secret argocd-initial-admin-secret -n argocd >/dev/null 2>&1; then
    echo "==> Suppression de argocd-initial-admin-secret (obsolete apres rotation)"
    kubectl delete secret argocd-initial-admin-secret -n argocd
  fi

  echo
  echo "==> Nouveau mot de passe admin ArgoCD :"
  echo "    $new_pwd"
  echo "    (a noter dans un gestionnaire de mots de passe, il ne sera plus jamais affiche)"
}

# -----------------------------------------------------------------------
# Mode grafana : mot de passe admin (SealedSecret monitoring/grafana-admin-sealed.yaml)
# -----------------------------------------------------------------------
rotate_grafana() {
  local secrets_file="$REPO_ROOT/monitoring/grafana-admin-sealed.yaml"
  [[ -f "$secrets_file" ]] || { echo "Introuvable: $secrets_file" >&2; exit 1; }

  echo "==> Rotation du mot de passe admin Grafana"
  confirm

  echo "==> Generation de la nouvelle valeur"
  local new_pwd
  new_pwd="$(gen_secret 32)"

  echo "==> Construction du Secret Kubernetes en clair (fichier temporaire, jamais commite)"
  local tmp_secret
  tmp_secret="$(mktemp)"
  trap 'rm -f "$tmp_secret"' RETURN

  cat > "$tmp_secret" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: grafana-admin
  namespace: monitoring
type: Opaque
stringData:
  admin-user: "admin"
  admin-password: "$new_pwd"
EOF

  echo "==> Chiffrement avec kubeseal"
  kubeseal --controller-namespace kube-system --format yaml < "$tmp_secret" > "$secrets_file"

  echo "==> Application immediate du secret au cluster"
  kubectl apply -f "$secrets_file"

  echo "==> Redemarrage de Grafana (stockage ephemere : reinitialisation propre depuis les env vars)"
  kubectl rollout restart deployment/monitoring-grafana -n monitoring
  kubectl rollout status deployment/monitoring-grafana -n monitoring --timeout=120s

  echo
  echo "==> Verification post-rotation"
  local check_ok=1
  local grafana_pod
  grafana_pod="$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana \
    --field-selector=status.phase=Running --sort-by=.metadata.creationTimestamp \
    -o name | tail -1 | cut -d/ -f2)"

  echo "--- Etat du pod ---"
  kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana

  echo "--- Logs Grafana ($grafana_pod) ---"
  local grafana_logs
  grafana_logs="$(kubectl logs -n monitoring "$grafana_pod" -c grafana --tail=100)"

  if echo "$grafana_logs" | grep -qi "HTTP Server Listen"; then
    echo "  [OK] serveur Grafana demarre"
  else
    echo "  [ECHEC] pas de confirmation de demarrage dans les logs Grafana"
    check_ok=0
  fi

  if echo "$grafana_logs" | grep -qiE 'error|fatal'; then
    echo "  [ATTENTION] lignes suspectes dans les logs Grafana, a verifier manuellement :"
    echo "$grafana_logs" | grep -iE 'error|fatal' | sed 's/^/      /'
  fi

  echo
  if [[ "$check_ok" -eq 1 ]]; then
    echo "==> Verification OK (readiness probe /api/health deja validee par le rollout ci-dessus)."
    echo "    Tu peux commiter $secrets_file dans Git (contenu chiffre, safe pour le repo)."
    echo "    Nouveau mot de passe admin Grafana : $new_pwd"
    echo "    (a noter dans un gestionnaire de mots de passe)"
  else
    echo "==> Verification ECHOUEE. Ne pas commiter tel quel : investigue avant de continuer." >&2
    exit 1
  fi
}

case "$MODE" in
  staging|production) rotate_app_secrets "$MODE" ;;
  argocd) rotate_argocd ;;
  grafana) rotate_grafana ;;
esac
