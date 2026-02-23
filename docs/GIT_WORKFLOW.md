# Git Workflow - Crypto-Bot

Sync bidirectionnel entre les 3 repos applicatifs.

## Organisation des repos

![Organisation des repos](../diagrams/05-repos-organisation.svg)

| Repo | Contenu | CI |
|------|---------|-----|
| **crypto-bot** | Orchestration, docker-compose, CI principal, scripts | Test + Build + Sync submodules + Deploy |
| **backend** | Code FastAPI (submodule de crypto-bot) | Test + Sync parent |
| **frontend** | Code Streamlit (submodule de crypto-bot) | Lint + Sync parent |
| **crypto-bot-infra** | Manifests K8s (Kustomize, ArgoCD) | Pas de CI (ArgoCD pull) |

## Pipeline CI/CD

![Pipeline CI/CD](../diagrams/04-pipeline-cicd.svg)

## Branches

| Branche | Role | Protection |
|---------|------|------------|
| `feature/*`, `dev_*` | Travail quotidien | Aucune |
| `staging` | Integration / test | MR requise, 0 approbation |
| `main` | Production | MR requise, 1+ approbation |

Les 3 repos app (crypto-bot, backend, frontend) ont les **memes branches**.
Le CI les synchronise automatiquement.


## Diagramme global

```mermaid
flowchart TB
    subgraph DEV["Developpeur"]
        D1[Travaille sur backend/]
        D2[Travaille sur frontend/]
        D3[Travaille sur les deux]
    end

    subgraph REPOS["Repos GitLab"]
        BE[backend repo]
        FE[frontend repo]
        CB[crypto-bot repo]
    end

    D1 -->|git push| BE
    D2 -->|git push| FE
    D3 -->|scripts/push.sh| CB

    subgraph CI_BE["CI Backend"]
        BE_TEST[lint + test]
        BE_SYNC[sync:parent]
    end

    subgraph CI_FE["CI Frontend"]
        FE_TEST[lint]
        FE_SYNC[sync:parent]
    end

    subgraph CI_CB["CI Crypto-bot"]
        CB_TEST[lint + test]
        CB_BUILD[build images]
        CB_SYNC[sync:submodules]
        CB_DEPLOY[deploy VM AWS]
    end

    BE -->|merge staging| CI_BE
    FE -->|merge staging| CI_FE
    CB -->|merge staging| CI_CB

    BE_TEST --> BE_SYNC
    FE_TEST --> FE_SYNC

    BE_SYNC -->|"update submodule pointer"| CB
    FE_SYNC -->|"update submodule pointer"| CB

    CB_TEST --> CB_BUILD
    CB_BUILD --> CB_SYNC
    CB_SYNC -->|"push commits"| BE
    CB_SYNC -->|"push commits"| FE
    CB_BUILD --> CB_DEPLOY

    subgraph K8S["Deploiement principal"]
        ARGOCD_NODE["ArgoCD<br/>auto-sync staging<br/>sync manuel prod"]
    end

    subgraph FALLBACK["Fallback VM AWS"]
        DOCKER["docker-compose<br/>(deploy SSH)"]
    end

    CB_BUILD -->|":staging / :production"| ARGOCD_NODE
    CB_DEPLOY -->|"SSH deploy"| DOCKER

    subgraph ANTIBOUCLE["Anti-boucle"]
        RULE["commit ci(...) → skip sync"]
    end

    style ANTIBOUCLE fill:#ff9,stroke:#f90
```


## Flux detaille : staging

### Cas A — Dev travaille sur un seul composant (backend)

```mermaid
sequenceDiagram
    participant Dev
    participant Backend as backend repo
    participant CI_BE as CI Backend
    participant CryptoBot as crypto-bot repo
    participant CI_CB as CI Crypto-bot
    participant Registry as GitLab Registry
    participant ArgoCD

    Dev->>Backend: git push origin feature/xxx
    Dev->>Backend: MR feature/xxx → staging
    Dev->>Backend: Merge MR

    Backend->>CI_BE: Pipeline staging
    CI_BE->>CI_BE: lint + test ✓
    CI_BE->>CryptoBot: sync:parent (update submodule pointer)
    Note over CI_BE,CryptoBot: commit "ci(backend): update to abc1234"

    CryptoBot->>CI_CB: Pipeline staging
    Note over CI_CB: Tests SKIPPED (commit ci(...))
    CI_CB->>Registry: build:docker → images :staging
    CI_CB->>Backend: sync:submodules SKIPPED (commit ci(...))
    CI_CB->>CI_CB: deploy:staging (VM AWS)

    ArgoCD->>ArgoCD: Detect new :staging images
    ArgoCD->>ArgoCD: Auto-sync K8s staging
```

### Cas B — Dev travaille sur les deux (backend + frontend)

```mermaid
sequenceDiagram
    participant Dev
    participant Backend as backend repo
    participant Frontend as frontend repo
    participant CryptoBot as crypto-bot repo
    participant CI_CB as CI Crypto-bot
    participant Registry as GitLab Registry
    participant ArgoCD

    Dev->>Dev: Modifie backend/ et frontend/
    Dev->>Dev: Commit dans chaque submodule + parent
    Dev->>CryptoBot: ./scripts/push.sh feature/xxx
    Note over Dev,CryptoBot: Push backend + frontend + crypto-bot

    Dev->>CryptoBot: MR feature/xxx → staging
    Dev->>CryptoBot: Merge MR

    CryptoBot->>CI_CB: Pipeline staging
    CI_CB->>CI_CB: lint + test ✓
    CI_CB->>Registry: build:docker → images :staging
    CI_CB->>Backend: sync:submodules → push staging branch
    CI_CB->>Frontend: sync:submodules → push staging branch
    Note over CI_CB,Frontend: commit normal → submodule CI SKIP sync (ci(...))
    CI_CB->>CI_CB: deploy:staging (VM AWS)

    ArgoCD->>ArgoCD: Auto-sync K8s staging
```

### Cas C — Passage en production

```mermaid
sequenceDiagram
    participant Lead as Tech Lead
    participant CryptoBot as crypto-bot repo
    participant CI_CB as CI Crypto-bot
    participant Registry as GitLab Registry
    participant ArgoCD

    Lead->>CryptoBot: MR staging → main
    Lead->>Lead: Code review + approbation
    Lead->>CryptoBot: Merge MR

    Lead->>CryptoBot: git tag v1.1
    Lead->>CryptoBot: git push origin v1.1

    CryptoBot->>CI_CB: Pipeline tag v1.1
    CI_CB->>CI_CB: lint + test ✓
    CI_CB->>Registry: build → images :v1.1 + :production
    CI_CB->>CI_CB: deploy:production (manuel)

    Lead->>ArgoCD: Sync manuel production
    ArgoCD->>ArgoCD: Deploy K8s production
```


## Anti-boucle

Le mecanisme qui empeche les boucles infinies :

```
crypto-bot merge → CI sync:submodules → push "ci(sync):..." sur backend
    → backend CI declenche → voit "ci(" → SKIP sync:parent → STOP ✓

backend merge → CI sync:parent → push "ci(backend):..." sur crypto-bot
    → crypto-bot CI declenche → voit "ci(" → SKIP sync:submodules → STOP ✓
```

**Regle unique** : si `$CI_COMMIT_MESSAGE` commence par `ci(`, tous les jobs sync sont ignores.


## Quand utiliser scripts/push.sh

| Situation | Commande | Pourquoi |
|-----------|----------|----------|
| Travail sur **backend** uniquement | `cd backend && git push` | Le sync:parent met a jour crypto-bot |
| Travail sur **frontend** uniquement | `cd frontend && git push` | Le sync:parent met a jour crypto-bot |
| Travail sur **les deux** depuis crypto-bot | `./scripts/push.sh` | Push les 3 repos d'un coup |
| Travail sur **CI/docker-compose** uniquement | `git push` | Pas de submodule a sync |


## Exemple concret : scripts/push.sh

Scenario : on a modifie le backend et le frontend depuis le repo crypto-bot.

```bash
# 1. On est dans crypto-bot/ sur la branche staging
cd ~/Crypto-bot
git checkout staging

# 2. Modifier le backend
cd backend
# ... editer des fichiers ...
git add .
git commit -m "feat: ajouter endpoint /v1/market/history"

# 3. Modifier le frontend
cd ../frontend
# ... editer des fichiers ...
git add .
git commit -m "feat: page historique marche"

# 4. Revenir au parent et commiter les references submodules
cd ..
git add backend frontend
git commit -m "feat: historique marche (backend + frontend)"

# 5. Tout pusher d'un coup avec push.sh
./scripts/push.sh staging
```

Ce que fait `push.sh` :
1. `cd backend && git push origin staging` (push le submodule d'abord)
2. `cd frontend && git push origin staging` (push le submodule d'abord)
3. `git push origin staging` (push le parent)

> **Pourquoi cet ordre ?** Si on pushait le parent en premier, la CI essaierait
> de sync les submodules mais les commits referencies n'existeraient pas encore
> sur le remote. En pushant les submodules d'abord, on s'assure que les SHA
> sont deja disponibles.


## Variables CI requises

### Variable de GROUPE (GitLab > Groupe dst_crypto > Settings > CI/CD > Variables)

| Variable | Valeur | Scope |
|----------|--------|-------|
| `GROUP_PAT_TOKEN` | PAT avec scopes `write_repository` + `read/write_registry` | Toutes branches |

> Un seul PAT, configure une seule fois au niveau du groupe.
> Accessible automatiquement par les 3 repos (backend, frontend, crypto-bot).

### Comment creer le GROUP_PAT_TOKEN

1. **Creer le PAT** : GitLab > Avatar (coin haut droit) > Edit profile > Access Tokens
   - Name : `group-ci-sync`
   - Expiration : 1 an max
   - Scopes : `write_repository`, `read_registry`, `write_registry`
   - Cliquer "Create personal access token"
   - **Copier le token** (commence par `glpat-`, affiche une seule fois)

2. **Ajouter comme variable de groupe** : GitLab > Groupe `dst_crypto` > Settings > CI/CD > Variables
   - Key : `GROUP_PAT_TOKEN`
   - Value : coller le PAT
   - Type : Variable
   - Protected : Non (sinon pas accessible sur staging)
   - Masked : Oui
   - Cliquer "Add variable"

> Le token est maintenant accessible dans les 3 repos (backend, frontend, crypto-bot)
> sans avoir a le configurer 3 fois.

### Variables supplementaires sur **crypto-bot** uniquement

| Variable | Valeur | Scope |
|----------|--------|-------|
| `SSH_PRIVATE_KEY` | Cle SSH pour deploy VM AWS | staging, prod |
| `VM_HOST` | `13.37.234.206` | staging, prod |
| `SSH_USER` | `ubuntu` | staging, prod |


## Protection des branches

### Sur les 3 repos (backend, frontend, crypto-bot)

| Branche | Push direct | MR | Approbations |
|---------|------------|-----|-------------|
| `staging` | Interdit (sauf CI token) | Oui | 0 (merge libre apres CI vert) |
| `main` | Interdit | Oui | 1 minimum |
