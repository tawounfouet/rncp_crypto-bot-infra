# Soutenance RNCP — Projet Crypto-Bot

Environnement de démonstration du projet **Crypto-Bot** : application (FastAPI + Streamlit
+ Airflow + ML) déployée en **Kubernetes local (Kind)**, avec monitoring et UIs d'admin.

> **Tout est déjà en place et validé.** Ce dossier est le point d'entrée : il décrit comment
> lancer/naviguer, et référence les dépôts.

## Dépôts

- **[crypto-bot-app/](https://gitlab.com/dst_crypto/Crypto-bot-app)** — code de l'application (backend, frontend, jobs Airflow, ML, Docker Compose, mode démo).
- **[crypto-bot-infra/](https://gitlab.com/dst_crypto/crypto-bot-infra)** — manifests Kubernetes (Kustomize, overlays `local*` pour Kind, ArgoCD, monitoring).

## Démarrage rapide — tout lancer en local (Kind)

Prérequis : `docker`, `kind`, `kubectl`, `helm`. (Tout depuis `crypto-bot-infra/`.)

```bash
cd crypto-bot-infra
./scripts/local-up.sh                 # 1. Kind + app (postgres, minio, backend, frontend, adminer)
./scripts/local-monitoring-up.sh      # 2. Prometheus + Grafana + Alertmanager
./scripts/local-services-up.sh        # 3. Airflow + MLflow + ml-api
./scripts/local-dashboard-up.sh       # 4a. UI Kubernetes : Headlamp
./scripts/local-dashboard-official-up.sh  # 4b. UI Kubernetes : Dashboard officiel
./scripts/local-demo-up.sh            # 5. Mode démo soutenance (worker de bots OFF + jeu de données)
```

Chaque script gère ses port-forwards. Après un `rollout`/changement de pod, relancer
`./scripts/port-forward.sh dev kind-crypto-bot`.

## Accès rapides

| Service | URL | Identifiants |
| :--- | :--- | :--- |
| Frontend (Streamlit) | http://localhost:8511 | `demo@cryptobot.dev` / `Demo12345!` |
| Backend (docs API) | http://localhost:8019/api/v1/docs | — |
| Airflow | http://localhost:8280 | `admin` / `admin` |
| MLflow | http://localhost:5081 | — |
| Grafana | http://localhost:3000 | `admin` / `admin` |
| Prometheus | http://localhost:9090 | — |
| Headlamp (UI K8s) | http://localhost:8090 | (sans token) |
| Dashboard officiel (UI K8s) | https://localhost:8443 | token (`CREDENTIALS.md`) |
| Adminer (UI PostgreSQL) | http://localhost:8085 | `postgres` / `postgres` |
| MinIO Console | http://localhost:9021 | `minioadmin` / `minioadmin` |

Comptes app : utilisateur `demo@cryptobot.dev` / `Demo12345!` · admin `admin@cryptobot.dev` / `Admin12345!`.
Liste complète des identifiants : **[CREDENTIALS.md](./CREDENTIALS.md)** (dev uniquement).

## Documentation

**Commencer ici :**
- **[INVENTAIRE_ACCES_LOCAL.md](./INVENTAIRE_ACCES_LOCAL.md)** — inventaire complet : accès, ports, identifiants,
  commandes, fichiers, validations, limites.
- **[CREDENTIALS.md](./CREDENTIALS.md)** — tous les identifiants de l'environnement local.

**Parcours / décisions (historique) :**
- **[DEPLOIEMENT_KIND_INFRA.md](./DEPLOIEMENT_KIND_INFRA.md)** — étude de faisabilité initiale du déploiement sur Kind.
- **[REMEDIATION_KIND_INFRA.md](./REMEDIATION_KIND_INFRA.md)** — corrections + implémentation de l'app sur Kind.
- **[PLAN_MONITORING_LOCAL.md](./PLAN_MONITORING_LOCAL.md)** — plan + statut du monitoring (Prometheus/Grafana).
- **[PLAN_SERVICES_RESTANTS_KIND.md](./PLAN_SERVICES_RESTANTS_KIND.md)** — plan + statut Airflow / MLflow / ml-api.

**Côté application :**
- [`crypto-bot-app/DEMO_SOUTENANCE.md`](https://gitlab.com/dst_crypto/Crypto-bot-app/-/blob/staging/DEMO_SOUTENANCE.md) — mode démonstration (seed, parcours, correctifs).
- [`crypto-bot-app/README.md`](https://gitlab.com/dst_crypto/Crypto-bot-app/-/blob/staging/README.md) — démarrage, architecture, audit.
