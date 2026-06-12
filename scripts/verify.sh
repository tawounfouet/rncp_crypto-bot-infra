#!/usr/bin/env bash
# =============================================================================
# verify.sh — Validation des manifests Kustomize (statique, sans cluster)
#
# Pour chaque overlay (dev/staging/prod) :
#   1. le build Kustomize aboutit ;
#   2. les ressources rendues sont valides au regard des schémas Kubernetes
#      (kubeconform ; les CRD sans schéma public, ex. SealedSecret, sont skip).
#
# Utilisable en local ET en CI (cf. .gitlab-ci.yml).
# Code de sortie : 0 si tout est OK, 1 sinon.
# =============================================================================
set -uo pipefail
cd "$(dirname "$0")/.."

# kustomize autonome si présent, sinon kubectl kustomize
if command -v kustomize >/dev/null 2>&1; then
  KBUILD() { kustomize build "$1"; }
elif command -v kubectl >/dev/null 2>&1; then
  KBUILD() { kubectl kustomize "$1"; }
else
  echo "ERREUR : ni 'kustomize' ni 'kubectl' disponible." >&2; exit 2
fi

HAVE_KUBECONFORM=0
command -v kubeconform >/dev/null 2>&1 && HAVE_KUBECONFORM=1

FAIL=0
ok() { printf "  \033[32m✓\033[0m %s\n" "$1"; }
ko() { printf "  \033[31m✗\033[0m %s\n" "$1"; FAIL=1; }

OVERLAYS="${*:-dev staging prod}"

for env in $OVERLAYS; do
  echo
  echo "== overlays/$env =="
  rendered="$(KBUILD "overlays/$env" 2>/tmp/verify-kustomize.err)"
  if [ $? -ne 0 ]; then
    ko "kustomize build a échoué"
    sed 's/^/      /' /tmp/verify-kustomize.err | head -5
    continue
  fi
  count=$(printf '%s\n' "$rendered" | grep -c '^kind:')
  ok "kustomize build OK ($count ressources)"

  if [ "$HAVE_KUBECONFORM" = "1" ]; then
    summary=$(printf '%s\n' "$rendered" | kubeconform -strict -summary -ignore-missing-schemas 2>&1)
    if printf '%s' "$summary" | grep -q "Invalid: 0, Errors: 0"; then
      ok "kubeconform : $(printf '%s' "$summary" | sed -n 's/.*Summary: //p')"
    else
      ko "kubeconform : $summary"
    fi
  else
    echo "  (kubeconform absent — validation de schémas ignorée)"
  fi
done

echo
if [ "$FAIL" = "0" ]; then
  echo -e "\033[32m✅ Manifests valides (build + schémas).\033[0m"; exit 0
else
  echo -e "\033[31m❌ Validation des manifests ÉCHOUÉE.\033[0m"; exit 1
fi
