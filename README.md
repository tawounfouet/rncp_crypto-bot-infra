# crypto-bot-infra

Manifests Kubernetes et configuration GitOps pour le projet **Crypto-Bot**.

> Diagrammes d'architecture : voir [ARCHITECTURE.md](docs/ARCHITECTURE.md) (Mermaid, rendu natif GitLab).

## Structure du repo

```
base/                   Manifests K8s communs (Deployments, Services, StatefulSets)
overlays/               Patches Kustomize par environnement (dev, staging, production)
argocd/                 Applications ArgoCD (staging, production, monitoring)
monitoring/             Stack Loki + Promtail + Grafana (SealedSecret + dashboard)
scripts/                Scripts utilitaires (port-forward.sh, verify.sh, rotate_secrets.sh)
docs/                   Documentation
```

## Documentation

| Document | Pour qui | Contenu |
|----------|----------|---------|
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
