# Roadmap Crypto-Bot

> Document de suivi global du projet. Spec MVP : `v1_architecture_app_streamlit.pdf`
>
> Issues GitLab : [crypto-bot](https://gitlab.com/dst_crypto/crypto-bot/-/issues)

---

## Vue d'ensemble

### Infrastructure

| Phase | Description | Statut |
|-------|-------------|--------|
| **1 — Cluster & Infrastructure** | | |
| 1.1 | Outils (talosctl, kubectl, helm, kubeseal...) | Done |
| 1.2 | Cluster Talos Proxmox (3 noeuds, bridge vmbr1, NAT) | Done |
| 1.3 | MetalLB, Ingress NGINX, local-path-provisioner, Namespaces | Done |
| **2 — Deploiements & GitOps** | | |
| 2.1 | Kustomize + Sealed Secrets + deploiements 3 envs (5/5 pods) | Done |
| 2.2 | ArgoCD (staging auto-sync, production sync manuel) | Done |
| **3 — CI/CD** | | |
| 3.1 | Pipeline GitLab CI — job `update-manifests` (GitOps ArgoCD) | Done |
| 3.2 | Sync bidirectionnel Git (submodules ↔ parent, anti-boucle) | Done |
| **4 — Monitoring & Outillage** | | |
| 4.1 | Loki + Promtail + Grafana (Helm, ArgoCD multi-source, dashboard) | Done |
| 4.2 | GitLab Runner self-hosted Proxmox (Docker executor, group runner) | Done |
| **5 — Acces & Resilience** | | |
| 5.1 | Cloudflare Tunnel + acces equipe | Plan pret |
| 5.2 | Backups CronJob + fallback VM AWS | Plan pret |

### Fonctionnel

| Phase | Description | Statut | Dependances |
|-------|-------------|--------|-------------|
| **6 — Qualite & Tests** | | | |
| 6.1 | Tests unitaires backend | A faire | — |
| 6.2 | Tests unitaires frontend | A faire | — |
| 6.3 | Tests d'integration API | A faire | — |
| 6.4 | Strategie de logging (Grafana) | A faire | — |
| **7 — Fondations techniques** | | | |
| 7.1 | Architecture frontend (structure, templating, style) | A faire | — |
| 7.2 | Figeage des versions (deps, images, CI) | A faire | — |
| 7.3 | Architecture donnees (historisation, multi-crypto) | A faire | — |
| **8 — Securite Binance & RGPD** | | | |
| 8.1 | Chiffrement cles API en BDD | A faire | 7 |
| 8.2 | Conformite RGPD (consentement, suppression, journalisation) | A faire | 8.1 |
| 8.3 | Backend endpoint credentials | A faire | 8.1 |
| 8.4 | Frontend section credentials (Page 5) | A faire | 8.3 |
| **9 — Portefeuille (Page 1)** | | | |
| 9.1 | Backend endpoints portfolio | A faire | 8 |
| 9.2 | Frontend Page 1 | A faire | 7.1, 9.1 |
| **10 — Bot & Trading (Pages 2 + 4)** | | | |
| 10.1 | Backend endpoints bots (CRUD, start/pause/stop, config) | A faire | 9 |
| 10.2 | Frontend Page 2 — Controle Bot | A faire | 7.1, 10.1 |
| 10.3 | Frontend Page 4 — Parametrage | A faire | 7.1, 10.1 |
| 10.4 | Strategie DCA | A faire | 10.1 |
| 10.5 | Strategie Grid Trading | A faire | 10.1 |
| **11 — Performances & Backtesting (Page 3)** | | | |
| 11.1 | Backend endpoints performance | A faire | 10 |
| 11.2 | Frontend Page 3 — Performances | A faire | 7.1, 11.1 |
| 11.3 | Backtesting des strategies | A faire | 7.3, 11.1 |
| **12 — Admin, Monitoring & Alertes (Pages 5 + 6)** | | | |
| 12.1 | Backend endpoints admin users | A faire | 8 |
| 12.2 | Backend proxy Prometheus | A faire | — |
| 12.3 | Frontend Page 5 — Admin | A faire | 7.1, 12.1 |
| 12.4 | Frontend Page 6 — Monitoring | A faire | 7.1, 12.2 |
| 12.5 | Dashboard Grafana admin (RGPD) | A faire | 12.1 |
| 12.6 | Alertes & notifications | A faire | 10 |
| **13 — Documentation utilisateur** | | | |
| 13.1 | Guide d'utilisation | A faire | 9-12 |
| 13.2 | Guide configuration Binance | A faire | 8 |
| 13.3 | FAQ et depannage | A faire | 9-12 |

---

## Phase 5 — Acces & Resilience

### 5.1 — Cloudflare Tunnel

> Acces public staging + production. ArgoCD et Grafana restent Tailscale-only.

**Etapes :**

- **A** : Setup Cloudflare (domaine, nameservers, tunnel, DNS)
- **B** : Manifests K8s GitOps (`cloudflare/` — deployment cloudflared, ConfigMap routes, SealedSecret credentials)
- **C** : Mise a jour Ingress (staging.DOMAINE, app.DOMAINE)
- **D** : Documentation (README, ARCHITECTURE, ONBOARDING)
- **E** : Verification (ArgoCD sync, pods, curl)

Fichiers a creer :

```
cloudflare/
  kustomization.yaml
  configmap.yaml                        # routes hostname → ingress-nginx
  deployment.yaml                       # cloudflare/cloudflared:2024.12.2, 2 replicas
  tunnel-credentials-sealed.yaml
argocd/
  cloudflare-app.yaml
```

### 5.2 — Backups production + Fallback VM AWS

> RPO 6h, RTO ~2min. MinIO non sauvegarde (donnees reproductibles).

**Architecture :**

- CronJob K8s toutes les 6h (00h, 06h, 12h, 18h UTC)
- 3 containers sequentiels : pg_dump → mongodump → SCP vers AWS
- Rotation 3 jours (~12 backups, ~6 GB max)

**Etapes :**

- **A** : Cle SSH K8s → AWS (SealedSecret)
- **B** : CronJob manifest (`overlays/prod/backup-cronjob.yaml`)
- **C** : Kustomization prod update
- **D** : Scripts fallback/restore sur AWS (`fallback.sh`, `restore-normal.sh`, `test-restore.sh`)
- **E** : Deploiement et test end-to-end

---

## Phase 6 — Qualite & Tests

> Parallelisable avec toutes les autres phases.

### 6.1 — Tests unitaires backend

- Completer la couverture (objectif a definir)
- Couvrir les domaines : auth, market, trading, strategy
- Mocks pour Binance API et BDD

### 6.2 — Tests unitaires frontend

- Tests des composants Streamlit
- Tests de l'AuthManager
- Mocks des appels API backend

### 6.3 — Tests d'integration API

- Tests end-to-end des flux principaux (auth → portfolio → trading)
- Environnement de test isole (fixtures BDD)
- CI : execution automatique sur chaque MR

### 6.4 — Strategie de logging

- Definir quoi loguer pour faciliter le debug via Grafana
- Niveaux de log coherents (INFO, WARNING, ERROR)
- Contexte structure (user_id, bot_id, trade_id, endpoint, duree)
- Labels Loki pour le filtrage

---

## Phase 7 — Fondations techniques

### 7.1 — Architecture frontend

- Structure des pages Streamlit (multi-page app via `st.navigation`)
- Systeme de templating / composants reutilisables
- Charte graphique et style (CSS custom, theme coherent)
- Composants partages : header, sidebar, notifications, formulaires, badges status
- Navigation et routing entre pages

### 7.2 — Figeage des versions

- requirements.txt backend + frontend : toutes deps pinnees (`==X.Y.Z`)
- Dockerfiles : images de base avec tags precis
- minio:latest → version pinnee (`RELEASE.YYYY-MM-DD...`)
- docker-compose AWS : tags d'images verifies
- Images CI : versions verifiees

### 7.3 — Architecture donnees

- Choix BDD pour l'historique (MongoDB collections vs PostgreSQL tables)
- Schema des donnees marche (OHLCV, orderbook, trades)
- Frequence de collecte (1min, 5min, 15min ?)
- Volumetrie estimee pour 1 paire (ex: BTC/USDT candles 1min = ~525 600 lignes/an)
- Strategie de retention et archivage
- Architecture multi-crypto : partitioning, indexation, scalabilite

---

## Phase 8 — Securite Binance & RGPD

### 8.1 — Chiffrement des cles API

- Chiffrement AES-256-GCM en BDD (PostgreSQL)
- Cle maitre (KEK) injectee via K8s Secret (pas en BDD)
- Cles API jamais exposees en clair dans les responses (masquage `****ABCD`)
- Formulaire write-only (on ecrit, on ne relit jamais en clair)

### 8.2 — Conformite RGPD

- Consentement explicite avant stockage des cles
- Droit de suppression (supprimer les cles a tout moment)
- Journalisation des acces aux donnees sensibles
- Politique de retention documentee

### 8.3 — Backend endpoint credentials

- `PUT /admin/users/{user_id}/binance-credentials` (body: api_key, api_secret, confirm_text)
- Validation de la connexion Binance avant stockage
- Confirmation forte (texte 'CONFIRMER')

### 8.4 — Frontend section credentials (Page 5)

- Affichage cle masquee (`****ABCD`)
- Formulaire remplacement (write-only)
- Confirmation forte

---

## Phase 9 — Portefeuille (Page 1 MVP)

> Ref : `v1_architecture_app_streamlit.pdf` — Page 1

### 9.1 — Backend endpoints

| Methode | Endpoint | Description |
|---------|----------|-------------|
| GET | `/status` | Statut backend + Binance |
| GET | `/portfolio/spot/overview?quote=USDT` | KPI (valeur totale, cash, nb actifs, nb ordres) |
| GET | `/portfolio/spot/balances?quote=USDT` | Table balances (Asset, Free, Locked, Total, Prix, Valeur, %) |
| GET | `/portfolio/spot/allocation?quote=USDT&top=10` | Graph allocation (top 10 + others) |
| GET | `/orders/open?market=spot` | Ordres ouverts |
| POST | `/orders/{order_id}/cancel` | Annuler un ordre |
| GET | `/trades/recent?market=spot&limit=50` | Derniers trades |

### 9.2 — Frontend Page 1

- Bandeau Status & Sync (badges OK/KO, timestamp, bouton rafraichir)
- KPI indicateurs cles (valeur totale USDT, cash dispo, nb actifs, nb ordres ouverts)
- Graph allocation (Donut/Bar — top 10 assets + others)
- Table Balances Spot (Asset | Free | Locked | Total | Prix | Valeur | %)
- Ordres ouverts (table + action annuler avec confirmation)
- Derniers trades (fills, details d'execution)

---

## Phase 10 — Bot & Trading (Pages 2 + 4 MVP)

> Ref : `v1_architecture_app_streamlit.pdf` — Pages 2 et 4

### 10.1 — Backend endpoints

| Methode | Endpoint | Description |
|---------|----------|-------------|
| GET | `/bots` | Liste des bots |
| GET | `/bots/{bot_id}/status` | Statut d'un bot |
| POST | `/bots/{bot_id}/start` | Demarrer un bot |
| POST | `/bots/{bot_id}/pause` | Mettre en pause |
| POST | `/bots/{bot_id}/stop` | Arreter (avec confirmation) |
| GET | `/bots/{bot_id}/config` | Config actuelle (strategie, version, updated_at) |
| POST | `/bots/{bot_id}/config/validate` | Valider une config |
| PUT | `/bots/{bot_id}/config` | Sauvegarder une config |

### 10.2 — Frontend Page 2 — Controle Bot

- Donnees critiques : bot selectionne, strategie, mode (Live/Paper), statut, heartbeat, derniere action
- Actions : Start, Pause, Stop (confirmation)
- Etats UI : RUNNING / STOPPED (+ transitoires STARTING / STOPPING)

### 10.3 — Frontend Page 4 — Parametrage

- Bandeau info bot (selectionne, statut, version config, derniere modif)
- Formulaire : dropdown strategie, sauvegarder, valider
- Etats UI : validation OK / erreurs lisibles

### 10.4 — Strategie DCA

- Dollar Cost Averaging : achat regulier a intervalle fixe
- Parametres : montant, frequence, paire, conditions d'arret

### 10.5 — Strategie Grid Trading

- Grille d'ordres buy/sell sur une plage de prix
- Parametres : bornes haute/basse, nombre de grilles, montant par grille

---

## Phase 11 — Performances & Backtesting (Page 3 MVP)

> Ref : `v1_architecture_app_streamlit.pdf` — Page 3

### 11.1 — Backend endpoints

| Methode | Endpoint | Description |
|---------|----------|-------------|
| GET | `/performance/summary?bot_id={id}&range=7d\|30d` | KPI agreges |
| GET | `/performance/equity?bot_id={id}&range=7d\|30d` | Equity curve (time series) |
| GET | `/performance/trades?bot_id={id}&range=7d\|30d` | Journal des trades |
| POST | `/internal/snapshots/portfolio` | Job interne : snapshot portefeuille |

### 11.2 — Frontend Page 3 — Performances

- Filtres : bot selectionne, periode (7j / 30j), derniere synchro, rafraichir
- KPI : PnL realise, ROI %, Max Drawdown, Win rate, Nb trades, Frais
- Graphique : Equity curve (time series)
- Journal des trades (timestamp, symbol, side, qty, price, fee, realized_pnl)

### 11.3 — Backtesting

- Execution de strategies sur donnees historiques
- Comparaison de resultats entre strategies
- Visualisation des resultats (metriques + equity curve simulee)

---

## Phase 12 — Admin, Monitoring & Alertes (Pages 5 + 6 MVP)

> Ref : `v1_architecture_app_streamlit.pdf` — Pages 5 et 6

### 12.1 — Backend endpoints admin

| Methode | Endpoint | Description |
|---------|----------|-------------|
| GET | `/admin/users` | Liste utilisateurs |
| GET | `/admin/users/{user_id}` | Fiche utilisateur |
| PATCH | `/admin/users/{user_id}` | Modifier role/statut |

### 12.2 — Backend proxy Prometheus

| Methode | Endpoint | Description |
|---------|----------|-------------|
| GET | `/monitoring/prometheus/queries` | Requetes Prometheus disponibles |
| GET | `/monitoring/prometheus/query?expr=...` | Proxy requete Prometheus |

### 12.3 — Frontend Page 5 — Admin

- Gestion utilisateurs : liste (email, role, statut, derniere connexion), fiche, enable/disable
- Section Securite Binance (cf. Phase 8.4)

### 12.4 — Frontend Page 6 — Monitoring

- Dashboard metriques : Prometheus (API up, DB up, bot up), latence, erreurs
- Controles : refresh, selecteur env (dev/prod) optionnel

### 12.5 — Dashboard Grafana admin

- Metriques business : nb utilisateurs, nb trades, volume, erreurs
- Respect RGPD : donnees agregees uniquement, pas de donnees personnelles

### 12.6 — Alertes & notifications

- Alertes prix (seuils configurables)
- Notifications execution d'ordres
- Canal : a definir (email, webhook, in-app)

---

## Phase 13 — Documentation utilisateur

### 13.1 — Guide d'utilisation

- Presentation des pages et fonctionnalites
- Captures d'ecran / GIFs

### 13.2 — Guide configuration Binance

- Creation API keys sur Binance
- Restrictions IP recommandees
- Connexion dans l'application

### 13.3 — FAQ et depannage

- Problemes courants et solutions
- Contact support

---

## Hygiene technique (transversal)

- [ ] NetworkPolicies / RBAC (isolation namespaces)
- [ ] Audit securite du code (injections, deps vulnerables)
- [ ] minio:latest → version pinnee

---

## Historique des phases completees

<details>
<summary>Phase 1 — Cluster & Infrastructure</summary>

- **1.1** : talosctl, kubectl, helm, kubeseal, argocd CLI installes
- **1.2** : Cluster Talos 3 noeuds sur Proxmox (bridge vmbr1 10.10.0.0/24, NAT)
- **1.3** : MetalLB v0.14.9 (L2), Ingress NGINX v1.12.0, local-path-provisioner v0.0.30, Namespaces staging/production/dev

</details>

<details>
<summary>Phase 2 — Deploiements & GitOps</summary>

- **2.1** : Kustomize (base + overlays dev/staging/prod), Sealed Secrets controller v0.29.0, SealedSecrets 3 envs, ImagePullSecrets gitlab-registry, 5/5 pods par env
- **2.2** : ArgoCD (namespace argocd, 7 pods), app staging auto-sync, app production sync manuel, repo GitLab connecte

</details>

<details>
<summary>Phase 3 — CI/CD</summary>

- **3.1** : Job `update:manifests` dans `.gitlab-ci.yml` — commit annotation `deployed-commit` dans crypto-bot-infra/main. Boucle complete : push staging → CI build → update:manifests → ArgoCD sync → rolling update. `imagePullPolicy: Always` sur backend.
- **3.2** : Sync bidirectionnel Git — `frontend/.gitlab-ci.yml` (lint + sync:parent), `sync:submodules` securise (controle ancestralite), anti-boucle retire de build/manifests. Variable CI `GROUP_PAT_TOKEN`. Doc `GIT_WORKFLOW.md`.

</details>

<details>
<summary>Phase 4 — Monitoring & Outillage</summary>

- **4.1** : ArgoCD Application multi-source — Helm chart `grafana/loki-stack` v2.10.3 (Loki + Promtail + Grafana) + manifests monitoring/ (SealedSecret grafana-admin + dashboard ConfigMap). Dashboard "Crypto-Bot Logs" provisionne auto. `ignoreDifferences` StatefulSet, `managedNamespaceMetadata` PodSecurity.
- **4.2** : VM Debian 13 (Trixie), Docker executor, group runner `proxmox-runner` dst_crypto. `concurrent = 2`, `pull_policy = ["if-not-present"]`, Docker socket mount. Shared runners desactives.

</details>

<details>
<summary>Refactorings realises (24/02/2026)</summary>

- **Backend** : architecture en couches → domaines (auth, market, trading, strategy, shared). 13/13 tests, 59 routes, 13 models.
- **Frontend** : auth PostgreSQL directe → API backend. Supprime psycopg2, bcrypt, yagmail, OTP.
- **Documentation** : incoherences corrigees (ARCHITECTURE_HYBRIDE, architecture-mermaid, tunnel SSH → Tailscale).

</details>
