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
        BE_SYNC["sync:parent\n→ crypto-bot"]
    end

    subgraph CI_FE["CI Frontend"]
        FE_TEST[lint]
        FE_SYNC["sync:parent\n→ crypto-bot"]
    end

    subgraph CI_CB["CI Crypto-bot"]
        CB_TEST["lint + test\n⛔ skip si ci(...)"]
        CB_BUILD["build images\n✅ tourne toujours"]
        CB_SYNC["sync:submodules\n⛔ skip si ci(...)\n🔍 controle ancestralite"]
        CB_MANIFESTS["update:manifests\n✅ tourne toujours"]
        CB_DEPLOY[deploy VM AWS]
    end

    BE -->|merge staging| CI_BE
    FE -->|merge staging| CI_FE
    CB -->|merge staging| CI_CB

    BE_TEST --> BE_SYNC
    FE_TEST --> FE_SYNC

    BE_SYNC -->|"commit ci(backend):..."| CB
    FE_SYNC -->|"commit ci(frontend):..."| CB

    CB_TEST --> CB_BUILD
    CB_BUILD --> CB_SYNC
    CB_SYNC -->|"push si parent ahead\nskip si submodule ahead"| BE
    CB_SYNC -->|"push si parent ahead\nskip si submodule ahead"| FE
    CB_BUILD --> CB_MANIFESTS
    CB_BUILD --> CB_DEPLOY
    CB_MANIFESTS -->|"commit infra"| INFRA

    subgraph K8S["Deploiement principal"]
        INFRA[crypto-bot-infra]
        ARGOCD_NODE["ArgoCD\nauto-sync staging\nsync manuel prod"]
    end

    subgraph FALLBACK["Fallback VM AWS"]
        DOCKER["docker-compose\n(deploy SSH)"]
    end

    INFRA --> ARGOCD_NODE
    CB_DEPLOY -->|"SSH deploy"| DOCKER

    subgraph ANTIBOUCLE["Anti-boucle"]
        RULE["commit ci(...) →\nskip tests + sync:submodules\nbuild + manifests tournent"]
    end

    style ANTIBOUCLE fill:#ff9,stroke:#f90
```


## Flux detaille : staging

### Cas A — Dev travaille sur un seul composant (ex: backend)

```mermaid
sequenceDiagram
    participant Dev
    participant Backend as backend repo
    participant CI_BE as CI Backend
    participant CryptoBot as crypto-bot repo
    participant CI_CB as CI Crypto-bot
    participant Registry as GitLab Registry
    participant Infra as crypto-bot-infra
    participant ArgoCD

    Dev->>Backend: git push origin dev_nath
    Dev->>Backend: MR dev_nath → staging
    Dev->>Backend: Merge MR

    Backend->>CI_BE: Pipeline staging
    CI_BE->>CI_BE: lint + test ✓
    CI_BE->>CryptoBot: sync:parent (update submodule pointer)
    Note over CI_BE,CryptoBot: commit "ci(backend): update to abc1234"

    CryptoBot->>CI_CB: Pipeline staging (commit ci(...))
    Note over CI_CB: Tests SKIPPED (anti-boucle ci(...))
    CI_CB->>Registry: build:docker → images :staging ✅
    Note over CI_CB: Build tourne meme sur ci(...)
    CI_CB->>Backend: sync:submodules → SKIPPED (anti-boucle ci(...))
    CI_CB->>Infra: update:manifests → annotation deployed-commit ✅
    CI_CB->>CI_CB: deploy:staging (VM AWS)

    ArgoCD->>Infra: Detect annotation change
    ArgoCD->>ArgoCD: Auto-sync K8s staging
```

> **Flux identique pour le frontend** : MR sur frontend → `sync:parent` → crypto-bot CI → build → deploy

### Cas B — Dev travaille sur les deux (backend + frontend)

```mermaid
sequenceDiagram
    participant Dev
    participant Backend as backend repo
    participant Frontend as frontend repo
    participant CryptoBot as crypto-bot repo
    participant CI_CB as CI Crypto-bot
    participant Registry as GitLab Registry
    participant Infra as crypto-bot-infra
    participant ArgoCD

    Dev->>Dev: Modifie backend/ et frontend/
    Dev->>Dev: Commit dans chaque submodule + parent
    Dev->>CryptoBot: ./scripts/push.sh dev_nath
    Note over Dev,CryptoBot: Push backend + frontend + crypto-bot

    Dev->>CryptoBot: MR dev_nath → staging
    Dev->>CryptoBot: Merge MR

    CryptoBot->>CI_CB: Pipeline staging
    CI_CB->>CI_CB: lint + test ✓
    CI_CB->>Registry: build:docker → images :staging

    Note over CI_CB,Frontend: sync:submodules avec controle ancestralite
    CI_CB->>Backend: push si parent ahead / skip si submodule ahead
    CI_CB->>Frontend: push si parent ahead / skip si submodule ahead
    Note over CI_CB,Frontend: commit normal → submodule CI voit ci(...) → skip sync:parent

    CI_CB->>Infra: update:manifests → annotation deployed-commit
    CI_CB->>CI_CB: deploy:staging (VM AWS)

    ArgoCD->>Infra: Detect annotation change
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

Le mecanisme qui empeche les boucles infinies sans bloquer le build :

```
Sens montant : backend merge staging
  → CI sync:parent → commit "ci(backend):..." sur crypto-bot staging
  → crypto-bot CI declenche :
      ⛔ tests SKIP          (commit ci(...))
      ✅ build:docker TOURNE (images :staging)
      ⛔ sync:submodules SKIP (commit ci(...)) → PAS de re-push → STOP ✓
      ✅ update:manifests TOURNE (annotation → ArgoCD sync)
      ✅ deploy:staging TOURNE (VM AWS)

Sens descendant : crypto-bot merge staging (commit normal)
  → CI sync:submodules → controle ancestralite :
      Si submodule ahead → SKIP (ne pas ecraser)
      Si parent ahead → push normal (pas de force-push)
  → push cree un commit sur backend/frontend staging
  → submodule CI declenche → sync:parent → commit "ci(...):" sur crypto-bot
  → crypto-bot CI → voit ci(...) → sync:submodules SKIP → STOP ✓
```

**Regle par job** (commit `ci(`) :

| Job | Skip sur `ci(` ? | Raison |
|-----|------------------|--------|
| `check:backend` | Oui | Deja teste dans le submodule |
| `lint:frontend` | Oui | Deja teste dans le submodule |
| `build:docker` | **Non** | Doit construire les nouvelles images |
| `sync:submodules` | Oui | Empeche la boucle infinie |
| `update:manifests` | **Non** | Doit mettre a jour ArgoCD |
| `deploy:staging` | **Non** | Doit deployer sur VM AWS |

### Controle d'ancestralite (sync:submodules)

Avant de push vers un submodule, `sync:submodules` verifie :

```
1. SHA identique      → "Already up to date" → skip
2. Submodule en avance → "AHEAD, skipping"    → skip (ne pas ecraser une MR mergee)
3. Parent en avance    → push normal           → PAS de --force
4. Push echoue         → warning               → intervention manuelle requise
```


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
