# crypto-bot-infra

Manifests Kubernetes et configuration GitOps pour le projet **Crypto-Bot**.

![Vue globale](diagrams/01-vue-globale.svg)

## Structure du repo

```
base/                   Manifests K8s communs (Deployments, Services, StatefulSets)
overlays/               Patches Kustomize par environnement (dev, staging, production)
argocd/                 Applications ArgoCD (staging, production, monitoring)
monitoring/             Stack Loki + Promtail + Grafana (SealedSecret + dashboard)
diagrams/               Diagrammes d'architecture (Excalidraw + SVG)
scripts/                Scripts utilitaires (port-forward.sh)
docs/                   Documentation
```

## Documentation

| Document | Pour qui | Contenu |
|----------|----------|---------|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Tout le monde | Decisions d'archi, choix technos, diagrammes |
| [ONBOARDING.md](docs/ONBOARDING.md) | Nouveaux membres | Acces cluster, kubectl, secrets, workflow dev |
| [GIT_WORKFLOW.md](docs/GIT_WORKFLOW.md) | Developpeurs | Branches, CI/CD, sync repos, variables |

## Liens rapides

- **ArgoCD** : `./scripts/port-forward.sh infra` puis https://localhost:8443
- **Grafana** : http://localhost:3000 (via port-forward infra)
- **Cluster** : `kubectl --context admin@crypto-bot get nodes`
