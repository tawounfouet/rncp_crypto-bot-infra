# Verification fonctionnelle multi-environnement (Ansible)

Playbook unique `verify.yml`, joue le meme role `verify` sur un inventaire different par
environnement. Le "test local dev" **est** ce playbook joue sur `inventories/dev` — pas un
script bash a part.

## Separation des responsabilites

- CI GitLab = teste le CODE (unitaires + integration).
- `scripts/check-infra.sh` (crypto-bot-app) = valide la CONFIG statique.
- **Ansible (ici) = teste l'ENVIRONNEMENT** : sante runtime des services + smoke fonctionnel
  Airflow (declenche le DAG d'ingestion et verifie l'artefact en base). Hors CI.
- Terraform (a venir, `crypto-bot-infra/terraform/`) = provisionne l'INFRA.

## Prerequis (poste de controle)

```bash
pipx install --include-deps ansible
pipx inject ansible docker kubernetes
ansible-galaxy collection install -r requirements.yml
```

## Invocation

```bash
cd crypto-bot-infra/ansible
ansible-playbook verify.yml -i inventories/dev          # local, stack docker compose dev
ansible-playbook verify.yml -i inventories/staging       # VM AWS, via SSH
ansible-playbook verify.yml -i inventories/production     # VM AWS, via SSH
ansible-playbook verify.yml -i inventories/k8s            # cluster Talos (backend/frontend uniquement)
```

- **dev** : stack demarree via `make dev-up && make dev-init` (crypto-bot-app). Necessite
  `AIRFLOW_FERNET_KEY` non vide dans `.env`.
- **staging/production** : necessitent un fichier `group_vars/vm_liora.yml` chiffre via
  `ansible-vault` (gitignore, jamais commite — meme VM Liora pour les deux, prefixe
  conteneur `staging-`/`prod-`). A creer localement :
  ```bash
  cat > group_vars/vm_liora.yml <<'EOF'
  vault_vm_host: CHANGEME
  vault_ssh_user: CHANGEME
  vault_ssh_private_key_path: CHANGEME
  EOF
  ansible-vault encrypt group_vars/vm_liora.yml   # puis `ansible-vault edit` pour remplir
  ansible-playbook verify.yml -i inventories/staging --ask-vault-pass
  ```
- **k8s** : necessite le contexte kubeconfig `admin@crypto-bot` et les routes Tailscale up.
  Verifie uniquement backend/frontend (seuls services qui tournent sur K8s aujourd'hui).

## Contrat de test

Chaque inventaire decrit dans son `group_vars/all.yml` :
- `services[]` : liste de checks de sante (`http`, `presence`, `pg_isready`).
- `smoke_dag` : le DAG a declencher (`ingest_ohlcv_binance_to_minio`) + la requete SQL qui
  prouve que l'artefact a ete produit. Absent sur l'inventaire k8s (pas d'Airflow sur K8s).

Le DAG `cryptobot_ml_pipeline` est volontairement exclu du smoke (etape `train-rf` cassee,
scikit-learn/torch absents de l'image Airflow — cf.
`orchestration/docs/04-troubleshooting.md` Probleme 8).

## Definition de "termine" (test local dev)

`ansible-playbook verify.yml -i inventories/dev` sort en 0 avec tous les `services[]` verts
et `SELECT count(*) FROM market_data WHERE exchange='binance'` > 0.
