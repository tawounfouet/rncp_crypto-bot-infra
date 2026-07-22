# Tests effectués — session Airflow / ports / IaC (2026-07-22)

Ce fichier récapitule les vérifications réellement exécutées (pas seulement écrites) pour
prouver le travail non commité de la session : ajout d'Airflow à staging/prod,
harmonisation des ports, fix SQLAlchemy, et mise en place du playbook Ansible `verify`.

## 1. Installation de l'outillage (poste de contrôle)

- `sudo apt install -y pipx` puis `pipx install --include-deps ansible` → Ansible core
  2.21.2 installé et isolé (venv pipx dédié, hors `.venv` du projet).
- `pipx inject ansible docker kubernetes` → SDK python nécessaires aux collections
  `community.docker` / `kubernetes.core` injectés dans le même venv.
- `ansible-galaxy collection install -r requirements.yml` → collections déjà présentes
  (embarquées avec la distribution `ansible` complète).
- `ansible-playbook verify.yml -i inventories/dev --syntax-check` → OK.

## 2. Relance Airflow dev

- Constat initial : `airflow-webserver` et `airflow-scheduler` en `Exited (255)` (workers
  gunicorn tués par manque de mémoire — hôte à ~7.4Gi RAM, sous pression). Les deux
  conteneurs s'étaient arrêtés à la même seconde exacte (`09:30:22`), signe d'un arrêt
  groupé plutôt que d'un crash indépendant.
- `docker restart airflow-scheduler airflow-webserver` → les deux repartent et tiennent
  (vérifié après 15s puis 45s, mémoire disponible descendue à ~1.9-2.3Gi mais stable).

## 3. Scaffolding `crypto-bot-infra/ansible/`

Arborescence complète créée (voir `README.md`) : `ansible.cfg`, `requirements.yml`,
`verify.yml`, inventaires `dev`/`staging`/`production`/`k8s` avec leurs `group_vars`, rôle
`verify` (tâches `docker_compose.yml`, `check_service.yml`, `smoke_dag.yml`, `k8s.yml`).

## 4. Premier run complet (dev) — échecs rencontrés et corrigés

| # | Symptôme | Diagnostic | Correction |
|---|----------|-----------|------------|
| 1 | Assert `expect` sur `airflow_webserver` échoue alors que la réponse HTTP contient bien la sous-chaîne attendue | La tâche `uri` ne retourne `content` que si `return_content: true` est explicite — sinon `.content` est vide | Ajout de `return_content: true` dans `check_service.yml` |
| 2 | `airflow dags state <dag_id> <run_id>` échoue en usage CLI (attend une `execution_date`, pas un `run_id`) — mais l'erreur passait inaperçue car `failed_when` ne cherchait que le mot `failed` dans stdout | Mauvaise commande CLI ; le run réel restait bloqué en `queued` sans que le playbook ne le détecte | Remplacement par une requête SQL directe sur `dag_run` (base `airflow`) filtrée par `run_id`, comparaison exacte de `state` |
| 3 | DAG jamais réellement exécuté : `collect_ohlcv`/`load_ohlcv` non importables (`No module named 'utils'`), erreur avalée silencieusement par un `try/except` dans le DAG (tâches "réussies" sans rien faire) | Nouvelle manifestation du gap connu #10 : `/opt/airflow/jobs` est ajouté au `sys.path` par le DAG, mais pas `/opt/airflow` (parent de `utils/`, pourtant bien monté/copié) — aucun `PYTHONPATH` n'était défini pour les services Airflow | Ajout de `PYTHONPATH=/opt/airflow` dans `docker-compose.yml` (anchor `x-airflow-common`), `docker-compose.staging.yml` et `docker-compose.prod.yml` (3 occurrences chacun) ; `make dev-up` pour recréer les conteneurs ; vérifié par import direct (`docker exec airflow-scheduler python -c "...from ingest.collect_ohlcv import run_ingestion..."` → OK) |
| 4 | Assert final `SELECT count(*) FROM market_data ...` échoue avec `relation "market_data" does not exist` malgré un run DAG réellement réussi et un upsert de 1000 lignes confirmé dans les logs de tâche | Le check interrogeait la base par défaut (`postgres`) au lieu de `crypto_bot_db` (nom réel de la base applicative, visible dans les logs de job : `Creating database engine for postgres:5432/crypto_bot_db`) | Ajout de `postgres_db: crypto_bot_db` dans chaque `group_vars/all.yml` et dans `smoke_dag`, requête corrigée avec `-d {{ smoke_dag.postgres_db }}` |

**Correction ≠ gap réel** : à un moment, l'échec de l'assert #4 a été (à tort) attribué à
"aucune création de schéma Postgres automatique". Vérification faite : le backend appelle
bien `init_database()` → `create_tables()` au démarrage (`backend/src/main.py` lifespan,
confirmé par les logs `✅ Database initialized successfully` et par `\dt` listant les 13
tables incluant `market_data`). Il n'y avait pas de gap distinct — seulement le même bug
de nom de base que la ligne précédente.

## 5. Run final — succès complet

Après les 4 corrections ci-dessus :

```
ansible-playbook verify.yml -i inventories/dev
```

`PLAY RECAP ... failed=0`. Vérifié concrètement :
- Les 9 checks de `services[]` (backend, frontend, ml_api, mlflow, minio, minio_console,
  postgres, airflow_webserver, airflow_scheduler) passent tous.
- Le DAG `ingest_ohlcv_binance_to_minio` unpause + trigger + run `success` réel (logs de
  tâche : appel Binance réel, 1000 klines récupérées, upsert Postgres confirmé).
- `SELECT count(*) FROM market_data WHERE exchange='binance'` → `2000` (> 0).

Ça valide end-to-end : l'ajout d'Airflow en dev, le fix SQLAlchemy (`utils/connectors/postgres.py`),
et — découverte pendant ce test — le fix PYTHONPATH nécessaire pour que les jobs Airflow
fonctionnent réellement (pas seulement s'importent sans planter au niveau DAG).

## 6. Non prouvé dans cette session

- **staging / production** : inventaires scaffoldés avec les valeurs de ports/préfixes
  connues (`docs/SETUP.md`), mais pas encore exécutés en réel — en attente de test SSH.
- **k8s** : inventaire scaffoldé (backend/frontend uniquement), pas exécuté — kubeconfig/
  Tailscale à vérifier.
