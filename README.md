# crypto-bot-infra

Manifests Kubernetes et configuration GitOps pour le projet **Crypto-Bot**.

> Diagrammes d'architecture : voir [ARCHITECTURE.md](docs/ARCHITECTURE.md) (Mermaid, rendu natif GitLab).

## Structure du repo

```
base/                   Manifests K8s communs (Deployments, Services, StatefulSets)
overlays/               Patches Kustomize : dev, staging, production (cluster distant)
                        + local, local-monitoring, local-services, local-dashboard,
                        local-dashboard-official, local-demo (cluster Kind local)
argocd/                 Applications ArgoCD (staging, production, monitoring)
monitoring/             Stack Loki + Promtail + Grafana (SealedSecret + dashboard) — cluster distant
scripts/                Scripts utilitaires (local-up/down, local-monitoring-up/down,
                        local-services-up/down, local-dashboard(-official)-up/down,
                        local-demo-up/down, port-forward.sh, verify.sh, rotate_secrets.sh)
docs/                   Documentation
```

## Démarrage rapide — tout lancer en local (Kind)

Prérequis : `docker`, `kind`, `kubectl`, `helm`.

```bash
# 1. Application (Kind + postgres, minio, backend, frontend, adminer)
./scripts/local-up.sh

# 2. Monitoring  Prometheus + Grafana + Alertmanager
./scripts/local-monitoring-up.sh

# 3. Services restants  Airflow + MLflow + ml-api
./scripts/local-services-up.sh

# 4. UI Kubernetes  Headlamp + Dashboard officiel
./scripts/local-dashboard-up.sh
./scripts/local-dashboard-official-up.sh

# 5. Mode démo soutenance (worker de bots OFF + jeu de données seedé)
./scripts/local-demo-up.sh
```

**Accès (ports)** — backend `8019`, frontend `8511`, Adminer `8085`, MinIO Console `9021`,
Airflow `8280`, MLflow `5081`, ML-API `8030`, Grafana `3000`, Prometheus `9090`,
Alertmanager `9093`, Headlamp `8090`, Dashboard `8443` (HTTPS).

**Identifiants** : voir [`CREDENTIALS.md`](../CREDENTIALS.md) — **dev uniquement**.
**Détail complet** (commandes, fichiers, validations, limites) : [`INVENTAIRE_ACCES_LOCAL.md`](../INVENTAIRE_ACCES_LOCAL.md).

**Arrêt** : `./scripts/local-demo-down.sh`, `local-dashboard-official-down.sh`,
`local-dashboard-down.sh`, `local-services-down.sh`, `local-monitoring-down.sh`,
puis `./scripts/local-down.sh [--purge]`.

## Documentation

| Document | Pour qui | Contenu |
|----------|----------|---------|
| [docs/local-kind/](docs/local-kind/README.md) | Jury / dev | **Environnement local Kind** : accès, identifiants, plans (monitoring, services, démo) |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Tout le monde | Decisions d'archi, choix technos, diagrammes |
| [ONBOARDING.md](docs/ONBOARDING.md) | Nouveaux membres | Acces cluster, kubectl, secrets, workflow dev |
| [GIT_WORKFLOW.md](docs/GIT_WORKFLOW.md) | Developpeurs | Branches, CI/CD, sync repos, variables |
| [INSTALL.md](docs/INSTALL.md) | Admin infra | Reconstruction du cluster depuis zero |
| [ROADMAP.md](docs/ROADMAP.md) | Jury / suivi | Historique des phases livrees, mapping referentiel |
| [GESTION_PROJET.md](docs/GESTION_PROJET.md) | Jury | RACI, objectifs SMART, methodologie, budget |
| [SECRETS_ET_TOKENS.md](docs/SECRETS_ET_TOKENS.md) | Admin infra | Cartographie complete PC/GitLab/K8s/VM, tokens, scellement EXCHANGE_ENC_KEY |

## Liens rapides

- **ArgoCD** : `./scripts/port-forward.sh infra` puis https://localhost:8443
- **Grafana** : http://localhost:3000 (via port-forward infra)
- **Cluster** : `kubectl --context admin@crypto-bot get nodes`
- **Cluster local (Kind)** : `kubectl get nodes` (guide de déploiement local : [DEPLOIEMENT_KIND_INFRA.md](../DEPLOIEMENT_KIND_INFRA.md))
