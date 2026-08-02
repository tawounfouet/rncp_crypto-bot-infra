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
  Tailscale à vérifier. **Note (2026-07-23)** : ce scope "backend/frontend uniquement" de
  `inventories/k8s/group_vars/all.yml` est maintenant **désynchronisé** de la réalité —
  `base/kustomization.yaml` déploie aussi `postgres`/`minio` sur K8s (corrigé dans
  `docs/SECRETS_ET_TOKENS.md` le 2026-07-23, une affirmation erronée disait le contraire).
  À mettre à jour dans une session ultérieure si l'inventaire k8s est repris.

---

# Procédure de test manuel par environnement

Checklist reproductible pour vérifier **à la main** (navigateur + `psql`) que tous les
ports exposés répondent et que toutes les bases sont accessibles, sur les 5 environnements
réellement déployés : **VM Liora** (staging, production — docker-compose) et **K8s Proxmox**
(dev, staging, production — namespaces séparés). Complémentaire du playbook Ansible
`verify.yml` (qui automatise une partie de ça) : ici l'angle est "je me connecte comme le
ferait une personne externe", pas juste un `curl` interne au conteneur.

Principe commun : un **tunnel SSH** (VM) ou **`kubectl port-forward`** (K8s) ouvre les
ports sur `localhost`, puis on ouvre chaque URL au navigateur et on se connecte à chaque
base avec `psql`/un client SQL.

## VM Liora — staging

**Prérequis** — récupérer host/user/clé sans les afficher en clair :
```bash
cd crypto-bot-infra/ansible
ansible-vault view group_vars/vm_liora.yml   # note VM_HOST / SSH_USER / chemin de cle
```

**Tunnel** (un seul `ssh`, tous les ports staging d'un coup) :
```bash
ssh -i <chemin_cle> \
  -L 8009:localhost:8009 -L 8501:localhost:8501 -L 8020:localhost:8020 \
  -L 5001:localhost:5001 -L 8080:localhost:8080 -L 9000:localhost:9000 \
  -L 9010:localhost:9010 -L 8085:localhost:8085 -L 5434:localhost:5434 \
  <SSH_USER>@<VM_HOST>
```
Laisser cette session SSH ouverte (elle sert juste de tunnel) et travailler depuis un
autre terminal / le navigateur.

**Checks HTTP** (ouvrir chaque URL, cocher si ça répond) :

| Service | URL | Attendu |
|---|---|---|
| Backend API | http://localhost:8009/api/v1/docs | Swagger UI |
| Frontend | http://localhost:8501 | App Streamlit |
| ml-api | http://localhost:8020/health | `{"status": "healthy"}` (ou equivalent) |
| mlflow-ui | http://localhost:5001 | UI MLflow |
| Airflow webserver | http://localhost:8080/home | Login Airflow |
| MinIO API | http://localhost:9000/minio/health/live | 200 vide |
| MinIO Console | http://localhost:9010 | Login MinIO |
| Adminer | http://localhost:8085 | Formulaire de connexion Adminer |

**Checks base de données** (3 bases sur la même instance Postgres, via le tunnel) :
```bash
psql -h localhost -p 5434 -U <POSTGRES_USER> -d crypto_bot_db -c '\dt'   # tables applicatives
psql -h localhost -p 5434 -U <POSTGRES_USER> -d airflow -c '\dt'         # metadata Airflow
psql -h localhost -p 5434 -U <POSTGRES_USER> -d mlflow -c '\dt'          # tracking MLflow
```
(<POSTGRES_USER>:  — cf. `.env` sur la VM)
(mot de passe : `POSTGRES_PWD` — cf. `.env` sur la VM, ne jamais le mettre dans ce fichier)

## VM Liora — production

Même tunnel, ports production (`Prod = Staging + 1` sur les ports externes, MinIO Console
et Adminer suivent leur propre convention — cf. `docs/SETUP.md`) :
```bash
ssh -i <chemin_cle> \
  -L 8010:localhost:8010 -L 8502:localhost:8502 -L 8021:localhost:8021 \
  -L 5002:localhost:5002 -L 8081:localhost:8081 -L 9001:localhost:9001 \
  -L 9011:localhost:9011 -L 8086:localhost:8086 -L 5435:localhost:5435 \
  <SSH_USER>@<VM_HOST>
```

| Service | URL | Attendu |
|---|---|---|
| Backend API | http://localhost:8010/api/v1/docs | Swagger UI |
| Frontend | http://localhost:8502 | App Streamlit |
| ml-api | http://localhost:8021/health | OK |
| mlflow-ui | http://localhost:5002 | UI MLflow |
| Airflow webserver | http://localhost:8081/home | Login Airflow |
| MinIO API | http://localhost:9001/minio/health/live | 200 vide |
| MinIO Console | http://localhost:9011 | Login MinIO |
| Adminer | http://localhost:8086 | **Profile `debug` : peut ne pas démarrer par défaut** (cf. `make prod-debug-up`) |

```bash
psql -h localhost -p 5435 -U postgres -d crypto_bot_db -c '\dt'
psql -h localhost -p 5435 -U postgres -d airflow -c '\dt'
psql -h localhost -p 5435 -U postgres -d mlflow -c '\dt'
```

## K8s Proxmox — dev / staging / production

Sur K8s, seuls **backend/frontend/postgres/minio** tournent (pas de ml-api/mlflow/airflow/
adminer — cf. asymétrie documentée dans `crypto-bot-infra/docs/SECRETS_ET_TOKENS.md`).
Le script `crypto-bot-infra/scripts/port-forward.sh` fait exactement le tunnel qu'il faut,
un jeu de ports différent par namespace pour pouvoir les lancer en parallèle :

```bash
cd crypto-bot-infra/scripts
./port-forward.sh dev          # ou staging / production
```

| Namespace | Backend | Frontend | PostgreSQL | MinIO API | MinIO Console |
|---|---|---|---|---|---|
| dev | 8019 | 8511 | 5442 | 9020 | 9021 |
| staging | 8109 | 8601 | 5532 | 9100 | 9101 |
| production | 8209 | 8701 | 5632 | 9200 | 9201 |

**Checks HTTP** (remplacer `<PORT>` par la ligne du namespace teste) :

| Service | URL | Attendu |
|---|---|---|
| Backend API | http://localhost:\<PORT_BACKEND\>/api/v1/docs | Swagger UI |
| Frontend | http://localhost:\<PORT_FRONTEND\> | App Streamlit |
| MinIO API | http://localhost:\<PORT_MINIO\>/minio/health/live | 200 vide |
| MinIO Console | http://localhost:\<PORT_MINIOC\> | Login MinIO |

**Check base de données** (une seule base ici, `crypto_bot_db` — pas d'Airflow/MLflow sur
K8s) :
```bash
psql -h localhost -p <PORT_PG> -U postgres -d crypto_bot_db -c '\dt'
```
(mot de passe : SealedSecret déchiffré côté cluster — cf. `overlays/<env>/secrets.yaml` et
`docs/SECRETS_ET_TOKENS.md` pour la chaîne de déchiffrement, ne jamais le mettre en clair
ici non plus)

## Definition de "tout est vert"

Pour un environnement donné : chaque URL de la table répond (pas de refus de connexion/
timeout — un formulaire de login compte comme "ça marche", pas besoin de s'authentifier),
et chaque `psql ... -c '\dt'` retourne une liste de tables sans erreur de connexion.
