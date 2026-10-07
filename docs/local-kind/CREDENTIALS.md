# Identifiants — Environnement local (Kind)

> [!WARNING]
> **Valeurs de développement locales uniquement.** Toutes jetables / placeholder, liées au
> cluster Kind `crypto-bot`. **Ne jamais réutiliser** en staging/production. Ce fichier
> contient des identifiants en clair : le **gitignorer** si tu ne veux pas le committer.
> Voir [`INVENTAIRE_ACCES_LOCAL.md`](./INVENTAIRE_ACCES_LOCAL.md) pour le détail des accès.

---

## 1. Application (démo soutenance)

| Rôle | Email | Mot de passe |
| :--- | :--- | :--- |
| Utilisateur démo | `demo@cryptobot.dev` | `Demo12345!` |
| Administrateur | `admin@cryptobot.dev` | `Admin12345!` |

Frontend : http://localhost:8511 (créés par `backend/scripts/seed_demo.py`, cf.
[`crypto-bot-app/DEMO_SOUTENANCE.md`](https://gitlab.com/dst_crypto/Crypto-bot-app/-/blob/staging/DEMO_SOUTENANCE.md)).

---

## 2. Services applicatifs / infra (namespace `dev`)

| Service | Utilisateur | Mot de passe | Remarque |
| :--- | :--- | :--- | :--- |
| **PostgreSQL** (5442) | `postgres` | `postgres` | bases : `crypto_bot_db`, `airflow`, `mlflow` |
| **MinIO** (9020 API / 9021 Console) | `minioadmin` | `minioadmin` | bucket `crypto-bot-data` |
| **Adminer** (8085) | `postgres` | `postgres` | serveur = `postgres`, base `crypto_bot_db` |
| **Airflow** (8280) | `admin` | `admin` | UI webserver |
| **MLflow** (5081) | — | — | aucune auth |
| **ML API** (8030) | — | — | `/health` |
| **Backend FastAPI** (8019) | — | — | auth JWT (comptes démo ci-dessus) |
| **Frontend Streamlit** (8511) | — | — | login = comptes démo |

---

## 3. Monitoring (namespace `monitoring`)

| Service | Port | Identifiants |
| :--- | :--- | :--- |
| **Grafana** | 3000 | `admin` / `admin` |
| **Prometheus** | 9090 | — (aucune auth) |
| **Alertmanager** | 9093 | — (aucune auth) |

---

## 4. UI Kubernetes

| UI | Port | Accès |
| :--- | :--- | :--- |
| **Headlamp** | 8090 | aucune auth (flag local `unsafeUseServiceAccountToken`) |
| **Dashboard officiel** | 8443 | token (compte `admin-user`) |

Token **longue durée** du Dashboard officiel (Secret `admin-user-token`) :

```bash
# copie directe dans le presse-papier (macOS)
kubectl --context kind-crypto-bot -n kubernetes-dashboard \
  get secret admin-user-token -o jsonpath='{.data.token}' | base64 -d | pbcopy

# ou affichage
kubectl --context kind-crypto-bot -n kubernetes-dashboard \
  get secret admin-user-token -o jsonpath='{.data.token}' | base64 -d; echo
```

Token Headlamp (uniquement si tu désactives le flag « unsafe ») :

```bash
kubectl --context kind-crypto-bot -n headlamp create token headlamp
```

---

## 5. Secrets de développement (backend / orchestration)

Posés en clair dans les overlays Kustomize (valeurs placeholder) :

| Variable | Valeur | Fichier |
| :--- | :--- | :--- |
| `JWT_SIGNING_KEY` | `dev-jwt-signing-key-not-for-production-0000000000` | `overlays/local/secret.yaml` |
| `EXCHANGE_ENC_KEY` | `AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=` | `overlays/local/secret.yaml` |
| `SECRET_KEY` | `dev-secret-key-not-for-production` | `overlays/local/secret.yaml` |
| `CORS_ORIGINS` | `http://localhost:8511,http://crypto-bot-frontend:8501` | `overlays/local/secret.yaml` |
| `ALLOWED_HOSTS` | `localhost,127.0.0.1,crypto-bot-backend` | `overlays/local/secret.yaml` |
| `AIRFLOW__CORE__FERNET_KEY` | `40QgSY-aB7VIH9shRgBZzJ3LGFMOVJyAmy3D0FE86c4=` | `overlays/local-services/secret-airflow.yaml` |
| `AIRFLOW__WEBSERVER__SECRET_KEY` | `dev-airflow-webserver-secret-not-for-production` | `overlays/local-services/secret-airflow.yaml` |
| `DEV_POSTGRES_USER/PWD` (Grafana) | `postgres` / `postgres` | `overlays/local-monitoring/secret-postgres-creds.yaml` |

---

## 6. Fichiers sources des identifiants

| Fichier | Contenu |
| :--- | :--- |
| `crypto-bot-infra/overlays/local/secret.yaml` | Postgres, MinIO, clés JWT/CORS backend |
| `crypto-bot-infra/overlays/local-services/secret-airflow.yaml` | Fernet key, webserver secret, admin Airflow |
| `crypto-bot-infra/overlays/local-monitoring/secret.yaml` | `grafana-admin` |
| `crypto-bot-infra/overlays/local-monitoring/secret-postgres-creds.yaml` | creds Postgres pour Grafana |
| `crypto-bot-infra/overlays/local-dashboard-official/token-secret.yaml` | token Dashboard officiel (`admin-user`) |
| `crypto-bot-app/.env` | secrets du chemin Docker Compose (réels, hors Kind) |

> Le cluster distant (Talos, contexte `admin@crypto-bot`) utilise des **SealedSecrets**
> déchiffrés par le contrôleur `sealed-secrets` — identifiants **différents** de ceux-ci.
