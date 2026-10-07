# Plan d'implémentation — Services restants (Airflow + MLflow + ml-api) sur Kind

> Objet : déployer sur le cluster Kind local **les services du `docker-compose.yml` de
> `crypto-bot-app` encore absents** — Airflow (webserver/scheduler/init), MLflow UI et
> l'API ML (ml-api) — dans la continuité de `overlays/local` (app) et
> `overlays/local-monitoring` (Prometheus/Grafana).
> Voir [INVENTAIRE_ACCES_LOCAL.md](./INVENTAIRE_ACCES_LOCAL.md).

## 1. Périmètre — services restants (issus de `docker-compose.yml`)

| Service compose | Image (déjà construite) | Port compose | Rôle |
| :--- | :--- | :--- | :--- |
| `airflow-webserver` | `crypto-bot-app-airflow-webserver` (via `orchestration/Dockerfile`) | 8080 | UI Airflow |
| `airflow-scheduler` | idem | — | ordonnanceur (LocalExecutor) |
| `airflow-init` | idem | — | `airflow db init` + connection + user admin |
| `crypto-bot-ml-api` | `crypto-bot-app-crypto-bot-ml-api` (via `models/Dockerfile`) | 8010 | API de prédiction FastAPI |
| `mlflow-ui` | idem `models/Dockerfile` (même image) | 5001 | UI MLflow |

Non concernés : `postgres`, `adminer`, `minio`, `createbuckets`, `backend`, `frontend`
(déjà en place). `REDIS_IMAGE` est déclaré dans `versions.env` mais **aucun service redis**
n'existe dans le compose → ignoré.

## 2. Contraintes identifiées (recon)

1. **Bases de données manquantes** : le compose crée `airflow` et `mlflow` via
   `init-scripts/init-user-db.sh` (exécuté à l'init du Postgres). Notre Postgres Kind
   (PVC déjà initialisé) **ne les a pas** → à créer (Job idempotent).
2. **Images déjà construites** (cache compose) : Airflow `2,03 Go` (ENTRYPOINT
   `dumb-init -- /entrypoint`, USER `airflow`), ML `2,51 Go`
   (`models/Dockerfile`, ENTRYPOINT `docker-entrypoint.sh` root→gosu `app`).
   → **pas de rebuild**, juste `docker tag` + `kind load`.
   ml-api et mlflow-ui partagent **la même image** (`models/Dockerfile`) → un seul tag.
3. **Airflow** a besoin d'env : `AIRFLOW__CORE__EXECUTOR=LocalExecutor`,
   `AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=.../airflow`, `AIRFLOW__CORE__FERNET_KEY`,
   `AIRFLOW__WEBSERVER__SECRET_KEY`, API basic auth, `MINIO_*`, `BINANCE_BASE_URL`.
4. **MLflow/ml-api** : backend store `.../mlflow` (Postgres), accès MinIO ;
   ml-api exige le dossier `artifacts`.
5. `/opt/airflow/logs` doit être inscriptible (emptyDir) ; `artifacts` partagé
   entre ml-api et mlflow-ui (PVC RWO, nœud unique → OK).
6. **Sûreté** : `DAGS_ARE_PAUSED_AT_CREATION=true` + `LOAD_EXAMPLES=false` → aucun DAG
   ne s'exécute (pas d'appels Binance/MinIO non voulus).

## 3. Décisions de conception

| Sujet | Choix |
| :--- | :--- |
| Overlay | **`overlays/local-services`** héritant de `../local` + ressources Airflow/ML (core app inchangé, opt-in) |
| Ports (schéma dev, distincts du compose) | Airflow **8280**, MLflow **5081**, ml-api **8030** |
| Images | `crypto-bot-app-airflow-webserver:latest` → tag `airflow:local` ; `crypto-bot-app-crypto-bot-ml-api:latest` → tag `ml:local` |
| Bases `airflow`/`mlflow` | Job `db-init` (image `postgres:14`, `CREATE DATABASE ... IF NOT EXISTS` idempotent) |
| Ordonnancement | `airflow-init` (initContainer qui attend `airflow` DB + main `airflow db init`), `mlflow-ui` (initContainer qui attend `mlflow` DB) |
| Secrets | nouveau Secret `airflow-secrets` (FERNET_KEY valide, WEBSERVER secret, admin user/pwd) |
| Volumes | Airflow logs = emptyDir ; `models-artifacts` = PVC 1Gi (partagé ml-api/mlflow-ui) ; data/logs ml-api = emptyDir |
| securityContext | non forcé pour ces pods (les images gèrent leur propre user : airflow UID 50000, models root→gosu) |

## 4. Livrables

```
crypto-bot-infra/
├── overlays/local-services/
│   ├── kustomization.yaml        # resources: ../local + ci-dessous
│   ├── secret-airflow.yaml       # fernet key + webserver secret + admin
│   ├── db-init-job.yaml          # crée les bases airflow + mlflow
│   ├── airflow.yaml              # init (Job) + webserver (Deploy+Svc) + scheduler (Deploy)
│   ├── mlflow.yaml               # ml-api (Deploy+Svc) + mlflow-ui (Deploy+Svc)
│   └── models-pvc.yaml           # PVC models-artifacts
└── scripts/
    ├── local-services-up.sh      # tag+load images, apply, wait, port-forwards
    └── local-services-down.sh
```

## 5. Étapes

1. Écrire l'overlay `overlays/local-services` (`kustomize build` doit passer).
2. Écrire `scripts/local-services-up.sh` : tag des 2 images → `kind load` → `apply -k`
   → attente (db-init, airflow-init, webserver, scheduler, ml-api, mlflow-ui) → port-forwards.
3. Étendre `scripts/port-forward.sh` (ports dev `8280`/`5081`/`8030`).
4. Déployer et valider.

## 6. Validation

```
db-init Job                          → Completed
airflow-init Job                     → Completed (airflow db init + user admin)
airflow-webserver                    → /health 200 ; UI http://localhost:8280 (admin/admin)
airflow-scheduler                    → Running
crypto-bot-ml-api                    → /health 200 (http://localhost:8030/health)
mlflow-ui                            → /health 200 (http://localhost:5081)
Postgres                             → bases airflow + mlflow + tables (~30 tables airflow)
```

## 7. Risques / limites

- **Chargement images** : ~4,5 Go de plus dans Kind (`kind load`) → quelques minutes.
- `airflow db init` : migrations ~1–2 min.
- **MLflow/artifacts** : PVC local-path (données éphémères si `--purge`).
- **Sécurité** : `airflow.cfg`/FERNET en clair (dev) ; à ne pas réutiliser ailleurs.
- ml-api : import torch (RAM) ; le nœud Kind a 47 Go → OK.
- Le **scheduler** en LocalExecutor peut consommer de la RAM ; à surveiller.

## 8. Décisions prises

1. **Emplacement** : overlay dédié **`overlays/local-services`** (hérite de `../local`).
2. **Ports** : schéma dev distinct — Airflow **8280**, MLflow **5081**, ml-api **8030**.

## 9. Statut d'implémentation

Implémenté et validé le 2026-10-07 sur `kind-crypto-bot`.

### Fichiers créés

| Fichier | Nature |
| :--- | :--- |
| `crypto-bot-infra/overlays/local-services/kustomization.yaml` | Overlay (hérite de `../local`) |
| `overlays/local-services/secret-airflow.yaml` | Fernet key + webserver secret + admin |
| `overlays/local-services/models-pvc.yaml` | PVC `models-artifacts` |
| `overlays/local-services/db-init-job.yaml` | Job `db-init` (bases `airflow` + `mlflow`) |
| `overlays/local-services/airflow.yaml` | ConfigMap + Job init + webserver + scheduler |
| `overlays/local-services/mlflow.yaml` | ml-api + mlflow-ui |
| `scripts/local-services-up.sh` / `local-services-down.sh` | **créés** |
| `scripts/port-forward.sh` | **modifié** — ports Airflow 8280 / MLflow 5081 / ml-api 8030 |

### Validé — run réel

```
kustomize build overlays/local-services   → OK (25 ressources)
kind load airflow:local + ml:local        → OK (réutilise les images compose)
db-init Job                               → Completed
airflow-init Job                          → Completed (db init + connection + user admin)
Pods                                      → airflow-webserver/scheduler, ml-api, mlflow-ui Running
Airflow  /health 200 ; UI 302 ; API /api/v1/dags (admin/admin) → 7 DAGs
MLflow   /health 200 ; expérience "Default" ; schéma 53 tables
ML API   /health 200
Postgres → bases airflow (42 tables) + mlflow (53 tables) + crypto_bot_db
```

### Accès

| UI | URL | Identifiants |
| :--- | :--- | :--- |
| Airflow | http://localhost:8280 | `admin` / `admin` |
| MLflow | http://localhost:5081 | — |
| ML API | http://localhost:8030/health | — |

```bash
./scripts/local-services-up.sh      # (prérequis : ./scripts/local-up.sh)
SKIP_FORWARD=1 ./scripts/local-services-up.sh
./scripts/local-services-down.sh    # retire Airflow/MLflow/ml-api (app conservée)
```

### Notes

- Les images **réutilisent le cache Compose** (pas de rebuild lourd) ; `kind load`
  ajoute ~4,5 Go au cluster.
- `airflow-webserver`/`scheduler` peuvent redémarrer **une fois** au premier déploiement
  (démarrent avant la fin de `airflow db init`) ; `airflow-init` garantit l'ordre pour la
  base, le redémarrage est automatique.
- DAGs **en pause** à la création (`DAGS_ARE_PAUSED_AT_CREATION=true`) → aucune exécution
  automatique (pas d'appels Binance/MinIO non voulus).
- **Fix OOM scheduler** : en `LocalExecutor`, les tâches s'exécutent DANS le pod scheduler.
  Si un DAG d'ingestion (16 tâches, pandas/minio/binance) est dé-pausé, plusieurs tâches
  parallèles font dépasser la RAM → `OOMKilled` (exit 137) + `BackOff`. Bornes ajoutées au
  ConfigMap : `PARALLELISM=4`, `MAX_ACTIVE_TASKS_PER_DAG=2`, `MAX_ACTIVE_RUNS_PER_DAG=1` ;
  limite mémoire scheduler relevée à `2Gi`. Vérifié : 0 redémarrage après application.
  Pour lancer un DAG en démo : le dé-pauser (`airflow dags unpause <id>` ou UI) puis
  « Trigger DAG » — il tournera désormais sous les bornes de parallélisme.

