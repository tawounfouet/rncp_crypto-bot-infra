# Inventaire — Déploiement local (Kind) : accès & liens

> Inventaire de ce qui a été implémenté et validé (2026-10-07) pour faire tourner le projet
> **en local sur Kubernetes (Kind)** : application `dev` + monitoring Prometheus/Grafana,
> et correctif du chemin Docker Compose.
> Voir aussi : [REMEDIATION_KIND_INFRA.md](./REMEDIATION_KIND_INFRA.md) ·
> [PLAN_MONITORING_LOCAL.md](./PLAN_MONITORING_LOCAL.md) ·
> [DEPLOIEMENT_KIND_INFRA.md](./DEPLOIEMENT_KIND_INFRA.md).

---

## 1. Vue d'ensemble

| Élément | Valeur |
| :--- | :--- |
| Cluster Kind | `crypto-bot` |
| Contexte kubectl | `kind-crypto-bot` |
| Namespace applicatif | `dev` |
| Namespace monitoring | `monitoring` |
| Kubernetes | v1.36.1 · StorageClass par défaut `standard` (local-path) |
| Release Helm monitoring | `monitoring` (`kube-prometheus-stack` **v92.1.0**) |
| Statut | ✅ app + services restants (Airflow/MLflow/ml-api) · monitoring 6/6 pods · 14/14 cibles Prometheus UP · UI Kubernetes (Headlamp + Dashboard officiel) |

---

## 2. Accès & identifiants

### 2.1 Application — namespace `dev`

Tous exposés via **port-forward** (pas d'Ingress sur Kind).

| Service | URL locale | Raccourci | Identifiants |
| :--- | :--- | :--- | :--- |
| **Backend FastAPI** | http://localhost:8019 — santé : `/health`, docs : `/api/v1/docs` | `svc/crypto-bot-backend:8009` | — |
| **Frontend Streamlit** | http://localhost:8511 | `svc/crypto-bot-frontend:8501` | — |
| **PostgreSQL 14** | `localhost:5442` (TCP, db `crypto_bot_db`) | `svc/postgres:5432` | `postgres` / `postgres` |
| **MinIO API (S3)** | http://localhost:9020 | `svc/minio:9000` | `minioadmin` / `minioadmin` |
| **MinIO Console** | http://localhost:9021 | `svc/minio:9001` | `minioadmin` / `minioadmin` |
| **Adminer (UI PostgreSQL)** | http://localhost:8085 | `svc/adminer:8080` | serveur `postgres`, `postgres` / `postgres`, base `crypto_bot_db` |
| **Airflow (UI)** | http://localhost:8280 | `svc/airflow-webserver:8080` | `admin` / `admin` |
| **MLflow (UI)** | http://localhost:5081 | `svc/mlflow-ui:5001` | — |
| **ML API (FastAPI)** | http://localhost:8030 — santé : `/health` | `svc/crypto-bot-ml-api:8010` | — |

Bucket S3 créé automatiquement : **`crypto-bot-data`** (Job `minio-createbuckets`).

> **Adminer** n'existe **que** dans l'overlay `local` (outil de dev, ajouté pour la parité
> Compose) : il est absent de `base/` et donc du cluster distant.
>
> **Airflow / MLflow / ML API** proviennent de l'overlay `local-services` (services restants
> du compose). Ports dev distincts : `8280` / `5081` / `8030`.
>
> **Mode démo soutenance** (overlay `local-demo`, cf.
> [`crypto-bot-app/DEMO_SOUTENANCE.md`](https://gitlab.com/dst_crypto/Crypto-bot-app/-/blob/staging/DEMO_SOUTENANCE.md)) : worker de
> bots désactivé (`ENABLE_BACKGROUND_TASKS=0`) + base peuplée par `seed_demo.py`. Comptes :
> `demo@cryptobot.dev` / `Demo12345!` et `admin@cryptobot.dev` / `Admin12345!`.
> `local-demo-up.sh` injecte aussi d'éventuelles **clés Spot Testnet**
> (`BINANCE_API_KEY_TEST`/`SECRET` du `.env`) via le secret `binance-demo-creds` (non commité)
> → soldes testnet live. Des clés **mainnet** sont rejetées par le testnet (`code -2015`).

### 2.2 Monitoring — namespace `monitoring`

| Service | URL locale | Identifiants |
| :--- | :--- | :--- |
| **Grafana** | http://localhost:3000 | `admin` / `admin` |
| **Prometheus** | http://localhost:9090 (cibles : http://localhost:9090/targets) | — |
| **Alertmanager** | http://localhost:9093 | — |

Composants internes (non exposés, scrapés) : `node-exporter`, `kube-state-metrics`,
`kube-prometheus-operator`.

- **Datasources Grafana** : `Prometheus` (uid `prometheus`), `Postgres Dev`
  (uid `crypto-bot-postgres` → `postgres.dev.svc.cluster.local:5432`), `Alertmanager`.
- **Dashboard projet** : **« Crypto-Bot - Projet (local Kind) »** (uid `crypto-bot-local`)
  → http://localhost:3000/d/crypto-bot-local
  (infra `dev` via Prometheus + données métier via PostgreSQL).

### 2.3 UI Kubernetes

**Headlamp** (moderne, CNCF) — namespace `headlamp`

| Service | URL locale | Accès |
| :--- | :--- | :--- |
| **Headlamp** | http://localhost:8090 | **sans token** en local (voir note) |

Le chart crée un `ClusterRoleBinding` **`headlamp-admin` → cluster-admin** pour son
ServiceAccount (`headlamp/headlamp`) → accès complet. En local, l'option
`config.unsafeUseServiceAccountToken: true` (cf. `overlays/local-dashboard/values.yaml`)
supprime le prompt de token. Comportement par défaut (prod) : Headlamp **demande un token**
→ `kubectl -n headlamp create token headlamp`.

**Kubernetes Dashboard officiel** — namespace `kubernetes-dashboard`

| Service | URL locale | Accès |
| :--- | :--- | :--- |
| **Dashboard** | https://localhost:8443 | token (compte `admin-user`) |

Version `v2.7.0`. Certificat auto-signé → accepter l'avertissement du navigateur.
Login > **Jeton** : utiliser le token **longue durée** (Secret `admin-user-token`, pas
d'expiration 1h comme `kubectl create token`) — copie directe dans le presse-papier :

```bash
kubectl --context kind-crypto-bot -n kubernetes-dashboard \
  get secret admin-user-token -o jsonpath='{.data.token}' | base64 -d | pbcopy
```

### 2.4 Identifiants de développement (jetables)

| Où | Fichier | Valeurs |
| :--- | :--- | :--- |
| App `dev` | `crypto-bot-infra/overlays/local/secret.yaml` | `postgres/postgres`, `minioadmin/minioadmin`, clés JWT/CORS de dev |
| Monitoring | `overlays/local-monitoring/secret.yaml` | Grafana `admin/admin` |
| Monitoring | `overlays/local-monitoring/secret-postgres-creds.yaml` | `DEV_POSTGRES_USER/PWD` |

> Valeurs **locales uniquement**, à ne jamais réutiliser en staging/production.

---

## 3. Commandes

```bash
cd crypto-bot-infra

# --- Application (Kind + 4 services socles) ---
./scripts/local-up.sh                 # déploie + port-forwards (ports dev 8019/8511/5442/9020/9021)
SKIP_FORWARD=1 ./scripts/local-up.sh  # déploie seulement
./scripts/local-down.sh               # supprime le namespace dev
./scripts/local-down.sh --purge       # supprime aussi le cluster Kind

# --- Monitoring (Prometheus + Grafana + Alertmanager) ---
./scripts/local-monitoring-up.sh      # installe le chart + port-forwards (3000/9090/9093)
SKIP_FORWARD=1 ./scripts/local-monitoring-up.sh
./scripts/local-monitoring-down.sh    # retire le monitoring (--keep-ns pour garder le ns)

# --- Services restants (Airflow + MLflow + ml-api) ---
./scripts/local-services-up.sh        # (prérequis : local-up.sh) + port-forwards 8280/5081/8030
SKIP_FORWARD=1 ./scripts/local-services-up.sh
./scripts/local-services-down.sh      # retire Airflow/MLflow/ml-api (app conservée)

# --- Mode démo soutenance (worker de bots OFF + seed) ---
./scripts/local-demo-up.sh            # rebuild+load backend/frontend, applique local-demo, seed
./scripts/local-demo-down.sh          # revient en mode normal (worker réactivé)

# --- UI Kubernetes (Headlamp) ---
./scripts/local-dashboard-up.sh       # déploie + port-forward 8090
./scripts/local-dashboard-down.sh     # retire Headlamp

# --- Kubernetes Dashboard officiel ---
./scripts/local-dashboard-official-up.sh    # déploie + port-forward 8443 (token admin-user)
./scripts/local-dashboard-official-down.sh  # retire le Dashboard officiel

# --- Port-forwards (générique, contexte paramétrable) ---
./scripts/port-forward.sh dev kind-crypto-bot   # app locale
./scripts/port-forward.sh infra                 # Grafana 3000 + ArgoCD 8443 (cluster distant)
```

Prérequis : `docker`, `kind`, `kubectl`, `helm`.

---

## 4. Fichiers créés / modifiés

### `crypto-bot-infra/`

| Chemin | Nature |
| :--- | :--- |
| `overlays/local/kustomization.yaml` | **créé** — overlay app Kind (images locales, `IfNotPresent`, initContainer wait-for-postgres) |
| `overlays/local/namespace.yaml` | **créé** — namespace `dev` |
| `overlays/local/secret.yaml` | **créé** — Secret app (clés obligatoires backend incluses) |
| `overlays/local/bucket-job.yaml` | **créé** — Job `mc mb` (bucket MinIO) |
| `overlays/local/adminer.yaml` | **créé** — Deployment + Service Adminer (UI PostgreSQL, local uniquement) |
| `overlays/local-services/kustomization.yaml` | **créé** — overlay services restants (hérite de `../local`) |
| `overlays/local-services/{secret-airflow,models-pvc,db-init-job,airflow,mlflow}.yaml` | **créé** — Airflow + MLflow + ml-api |
| `scripts/local-services-up.sh` / `local-services-down.sh` | **créé** |
| `overlays/local-dashboard/values.yaml` | **créé** — valeurs Helm Headlamp (UI Kubernetes) |
| `scripts/local-dashboard-up.sh` / `local-dashboard-down.sh` | **créé** |
| `overlays/local-dashboard-official/{admin-user,token-secret,kustomization}.yaml` | **créé** — compte admin + token longue durée du Dashboard officiel |
| `scripts/local-dashboard-official-up.sh` / `local-dashboard-official-down.sh` | **créé** |
| `overlays/local-demo/kustomization.yaml` | **créé** — mode démo (worker de bots OFF sur le backend) |
| `scripts/local-demo-up.sh` / `local-demo-down.sh` | **créé** — rebuild+load + seed (`seed_demo.py --reset`) |
| `overlays/local-monitoring/kustomization.yaml` | **créé** |
| `overlays/local-monitoring/namespace.yaml` | **créé** — namespace `monitoring` |
| `overlays/local-monitoring/secret.yaml` | **créé** — `grafana-admin` |
| `overlays/local-monitoring/secret-postgres-creds.yaml` | **créé** — creds Postgres dev |
| `overlays/local-monitoring/values.yaml` | **créé** — valeurs Helm kube-prometheus-stack |
| `overlays/local-monitoring/dashboard-crypto-bot-local.yaml` | **créé** — dashboard projet (18 panneaux) |
| `scripts/local-up.sh` / `local-down.sh` | **créé** |
| `scripts/local-monitoring-up.sh` / `local-monitoring-down.sh` | **créé** |
| `scripts/port-forward.sh` | **modifié** — contexte kubectl en 2ᵉ argument |
| `README.md` | **modifié** — structure |

### `crypto-bot-app/`

| Chemin | Nature |
| :--- | :--- |
| `versions.env` | **modifié** — `MINIO_IMAGE`/`MINIO_MC_IMAGE` → `pgsty` (images officielles MinIO supprimées en 2026) |

### `rncp_soutenance/` (documentation)

| Fichier | Rôle |
| :--- | :--- |
| [DEPLOIEMENT_KIND_INFRA.md](./DEPLOIEMENT_KIND_INFRA.md) | Étude de faisabilité initiale (Gemini) |
| [REMEDIATION_KIND_INFRA.md](./REMEDIATION_KIND_INFRA.md) | Corrections + implémentation app Kind |
| [PLAN_MONITORING_LOCAL.md](./PLAN_MONITORING_LOCAL.md) | Plan + implémentation monitoring local |
| [PLAN_SERVICES_RESTANTS_KIND.md](./PLAN_SERVICES_RESTANTS_KIND.md) | Plan + implémentation Airflow/MLflow/ml-api |
| **INVENTAIRE_ACCES_LOCAL.md** (ce fichier) | Inventaire des accès et liens |

---

## 5. Validations effectuées

| Contrôle | Résultat |
| :--- | :--- |
| App : 5 pods `Running`/`Completed` | ✅ |
| App : PVC postgres 5Gi + minio 10Gi `Bound` | ✅ |
| App : backend sur **PostgreSQL** (pas fallback SQLite) | ✅ 21 tables + 2 `bot_templates` |
| App : bucket MinIO `crypto-bot-data` | ✅ |
| App : Adminer — pod `Running`, http://localhost:8085 → 200, TCP `postgres:5432` OK | ✅ |
| App : `GET /health` 200 · `/api/v1/docs` 200 · frontend 200 | ✅ |
| Monitoring : 6 pods `Running` | ✅ |
| Monitoring : cibles Prometheus **14/14 UP** | ✅ |
| Monitoring : datasource Postgres `Database Connection OK` | ✅ |
| Monitoring : dashboard projet chargé | ✅ |
| Compose : `make dev-config` + `createbuckets` (bucket créé) | ✅ |
| Services restants : Airflow `/health` 200, 7 DAGs (admin/admin), base airflow 42 tables | ✅ |
| Services restants : MLflow `/health` 200, 53 tables, exp. « Default » ; ml-api `/health` 200 | ✅ |
| UI Kubernetes : Headlamp pod `Running`, http://localhost:8090 → 200, CRB `headlamp-admin` | ✅ |
| UI Kubernetes : Dashboard officiel `Running`, https://localhost:8443 → 200, API avec token admin-user → 200 | ✅ |
| Démo : seed appliqué (users=3, bots=3, backtests=3, market_data=2882) ; login démo + admin → 200 | ✅ |

---

## 6. Limites connues

- **Tables métier vides** en local (seul `bot_templates` a les 2 seeds) → le dashboard affiche 0 pour users/orders/transactions.
- **Dashboards d'origine** (`grafana-dashboard-infra.yaml`, `grafana-dashboard-crypto-bot.yaml`) **non chargés** : ils dépendent du plugin Infinity (sondes VM AWS) et de **Loki** (logs), absents en local.
- **Pas de logs** (Loki/Promtail non déployés en v1).
- **Airflow/MLflow** : images ~4,5 Go chargées dans Kind ; Airflow webserver/scheduler peuvent redémarrer 1× au premier déploiement (avant la fin de `airflow db init`) ; logs Airflow en `emptyDir` (éphémères) ; DAGs en pause (aucune exécution auto).
- **Airflow — LocalExecutor** : les tâches tournent dans le pod scheduler ; un DAG d'ingestion dé-pausé peut saturer sa RAM (`OOMKilled`). Bornes appliquées : `PARALLELISM=4`, `MAX_ACTIVE_TASKS_PER_DAG=2`, scheduler `2Gi`. Un DAG n'est **pas** dé-pausé par défaut — 7/7 en pause.
- **MLflow artifacts** : PVC local-path (perdu avec `local-down.sh --purge`).
- **Cluster distant** (`admin@crypto-bot`) absent de ce poste : `port-forward.sh infra`/`./scripts/local-up.sh` ne visent que le Kind local. Le **sealed secret distant** (`JWT_SIGNING_KEY`/`CORS_ORIGINS`/`ALLOWED_HOSTS`) reste à vérifier côté prod.
- `local-monitoring-down.sh` laisse les **CRD** cluster-scoped de kube-prometheus-stack (comportement Helm) ; `local-down.sh --purge` nettoie tout le cluster.

---

- **Headlamp** : en local, `unsafeUseServiceAccountToken: true` (authentifie tout le monde en tant que SA du pod) — **défaut à ne pas garder en prod** ; comportement par défaut = login par token.
- **Dashboard officiel** : `v2.7.0` (projet peu maintenu ; fonctionne sur k8s 1.36 mais pas de garantie de support long terme) ; HTTPS auto-signé. Utiliser le token **longue durée** (`admin-user-token`) : `kubectl create token` expire en 1h → `Unauthorized (401)` si expiré ou tronqué au copier-coller.

## 7. Reproduire depuis zéro

```bash
cd crypto-bot-infra
./scripts/local-up.sh                 # cluster Kind + app (dev)
./scripts/local-monitoring-up.sh      # monitoring (Prometheus/Grafana)
./scripts/local-services-up.sh        # Airflow + MLflow + ml-api
./scripts/local-dashboard-up.sh       # UI Kubernetes (Headlamp)
./scripts/local-dashboard-official-up.sh  # (option) Dashboard officiel (token)
./scripts/local-demo-up.sh            # (option) mode démo soutenance (worker OFF + seed)
# → Grafana http://localhost:3000 (admin/admin) → dashboard "Crypto-Bot - Projet (local Kind)"
# → Frontend démo http://localhost:8511 (demo@cryptobot.dev / Demo12345!)
```
