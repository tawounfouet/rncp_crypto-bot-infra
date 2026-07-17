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
| 6.1 | Tests unitaires backend | Partiel | — |
| 6.2 | Tests unitaires frontend | Partiel | — |
| 6.3 | Tests d'integration API | A faire | — |
| 6.4 | Strategie de logging (Grafana) | A faire | — |
| **7 — Fondations techniques** | | | |
| 7.1 | Architecture frontend (structure, templating, style) | Partiel | — |
| 7.2 | Figeage des versions (deps, images, CI) | Partiel | — |
| 7.3 | Architecture donnees (historisation, multi-crypto) | Partiel | — |
| 7.4 | Visualisation de donnees (outil dedie, RGAA) | A faire | 7.3 |
| 7.5 | Pipeline ETL formel (collecte → transformation → stockage) | Partiel | 7.3 |
| **8 — Securite Binance & RGPD** | | | |
| 8.1 | Chiffrement cles API en BDD | A faire | 7 |
| 8.2 | Conformite RGPD (consentement, suppression, journalisation) | A faire | 8.1 |
| 8.3 | Backend endpoint credentials | A faire | 8.1 |
| 8.4 | Frontend section credentials (Page 5) | A faire | 8.3 |
| **9 — Portefeuille (Page 1)** | | | |
| 9.1 | Backend endpoints portfolio | Partiel | 8 |
| 9.2 | Frontend Page 1 | A faire | 7.1, 9.1 |
| **10 — Bot & Trading (Pages 2 + 4)** | | | |
| 10.1 | Backend endpoints bots (CRUD, start/pause/stop, config) | Partiel | 9 |
| 10.2 | Frontend Page 2 — Controle Bot | A faire | 7.1, 10.1 |
| 10.3 | Frontend Page 4 — Parametrage | A faire | 7.1, 10.1 |
| 10.4 | Strategie DCA | A faire | 10.1 |
| 10.5 | Strategie Grid Trading | A faire | 10.1 |
| **11 — Performances & Backtesting (Page 3)** | | | |
| 11.1 | Backend endpoints performance | Partiel | 10 |
| 11.2 | Frontend Page 3 — Performances | A faire | 7.1, 11.1 |
| 11.3 | Backtesting des strategies | A faire | 7.3, 11.1 |
| 11.4 | Algorithme d'intelligence artificielle (C12) | A faire | 7.3, 11.1 |
| **12 — Admin, Monitoring & Alertes (Pages 5 + 6)** | | | |
| 12.1 | Backend endpoints admin users | Partiel | 8 |
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
- 2 containers sequentiels : pg_dump → SCP vers AWS
- Rotation 3 jours (~12 backups, ~6 GB max)

**Etapes :**

- **A** : Cle SSH K8s → AWS (SealedSecret)
- **B** : CronJob manifest (`overlays/production/backup-cronjob.yaml`)
- **C** : Kustomization prod update
- **D** : Scripts fallback/restore sur AWS (`fallback.sh`, `restore-normal.sh`, `test-restore.sh`)
- **E** : Deploiement et test end-to-end

---

## Phase 6 — Qualite & Tests

> Parallelisable avec toutes les autres phases.

### 6.1 — Tests unitaires backend — Partiel

**Existant :**
- `test_auth_service.py` (113 lignes) : hashing, tokens, sessions, JWT
- `test_client_binance.py` (154 lignes) : init, API calls, erreurs, testnet
- Structure pytest en place (`tests/unit/`, `tests/integration/`, `conftest.py`)
- CI : pytest avec coverage dans pipeline backend + parent

**A completer :**
- Couverture domaines manquants : market, trading, strategy
- Mocks pour Binance API et BDD
- Objectif couverture a definir

### 6.2 — Tests unitaires frontend — Partiel

**Existant :**
- `test_auth.py` : script basique (health check, validation email, password strength)
- CI : flake8 + black (pas de pytest)

**A completer :**
- Tests des composants Streamlit (pages)
- Tests de l'AuthManager (necessite mock session_state)
- Mocks des appels API backend
- Integration pytest dans CI frontend

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

### 7.1 — Architecture frontend — Partiel

**Existant :**
- Structure multi-page (`navigation.py` routeur, pages login/signup/app/info)
- Module auth complet (api_client, auth_manager, config, utils, migration guide)
- Systeme de badges environnement (dev/staging/prod)
- Session state management (tokens, user_data, page routing)
- Sidebar avec info utilisateur + logout

**A completer :**
- Page app = placeholder ("Hello World") — pas de contenu metier
- Systeme de templating / composants reutilisables
- Charte graphique et style (CSS custom, theme coherent)
- Composants partages : header, notifications, formulaires, badges status
- Accessibilite (RGAA) : contrastes, navigation clavier, labels

### 7.2 — Figeage des versions — Partiel

**Existant :**
- Backend requirements.txt : deps pinnees (FastAPI==0.104.1, pandas==2.2.3, etc.)
- Frontend requirements.txt : deps pinnees (streamlit==1.37.1, requests==2.32.3, etc.)
- Dockerfiles : python:3.11-slim, postgres:14
- MinIO pinne (`RELEASE.2024-12-18T13-15-44Z`) dans K8s

**A completer :**
- docker-compose AWS : verifier tags d'images (postgres)
- Images CI : versions a verifier

### 7.3 — Architecture donnees — Partiel

**Existant :**
- 6 modeles SQLAlchemy : User, Strategy, StrategyDeployment, Order, Transaction, MarketData
- Schema MarketData : symbol, interval, OHLCV, volume metrics, timestamps
- PostgreSQL pour donnees structurees
- UUID primary keys, index, soft delete, JSON parameters

**A completer :**
- Document formel d'architecture donnees
- Frequence de collecte definie (1min, 5min, 15min ?)
- Volumetrie estimee et strategie de retention
- Architecture multi-crypto : partitioning, indexation, scalabilite

### 7.4 — Visualisation de donnees (C10)

- Outil de visualisation dedie (Streamlit/Plotly — argumenter vs Power BI/Tableau)
- Dashboard qualite et integrite des donnees
- Visualisation accessible et comprehensible (RGAA)
- Choix de l'outil justifie en lien avec les typologies de donnees

### 7.5 — Pipeline ETL formel (C11) — Partiel

**Existant :**
- MarketDataInsertService : collecte Binance → indicateurs techniques → UPSERT PostgreSQL
- Indicateurs calcules : SMA, EMA, RSI, Bollinger Bands, MACD
- Endpoint `POST /market/data/insert` (insertion manuelle)

**A completer :**
- Automatisation (scheduler / Airflow ou CronJob K8s)
- Documentation formelle du processus ETL
- Tests de validation du pipeline
- Gestion des erreurs documentee
- Securite des donnees dans le pipeline

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

## Phase 9 — Portefeuille (Page 1 MVP) — Partiel

> Ref : `v1_architecture_app_streamlit.pdf` — Page 1

### 9.1 — Backend endpoints — Partiel

**Endpoints existants (a adapter/renommer) :**
- `GET /health` + `GET /health/detailed` (statut backend + BDD)
- `GET /trading/portfolio` (holdings actuels)
- `GET /trading/positions` (positions ouvertes avec P&L)
- `GET /trading/orders` (liste ordres, filtrable)
- `POST /trading/orders` (creer un ordre)
- `GET /trading/statistics` (stats PnL, win rate)
- `GET /market/price/{symbol}` + `GET /market/prices` (prix temps reel)

**Endpoints a creer/adapter pour MVP :**

| Methode | Endpoint | Description |
|---------|----------|-------------|
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

## Phase 10 — Bot & Trading (Pages 2 + 4 MVP) — Partiel

> Ref : `v1_architecture_app_streamlit.pdf` — Pages 2 et 4

### 10.1 — Backend endpoints — Partiel

**Endpoints existants (strategies + deployments) :**
- `GET /strategies/available` (types de strategies disponibles)
- `GET/POST /strategies/` (CRUD strategies utilisateur)
- `GET/PUT/DELETE /strategies/{id}` (detail, update, soft delete)
- `POST /strategies/{id}/deploy` (deployer pour trading)
- `GET /strategies/deployments/` (liste deployments)
- `POST /strategies/deployments/{id}/stop` (arreter)
- `POST /strategies/validate` (valider parametres)

**4 strategies implementees :**
- MovingAverageCrossover (fast/slow MA)
- RSIReversal (mean reversion RSI)
- BollingerBands (breakout/squeeze)
- MultiIndicator (MA+RSI+BB combines)

**Pas encore implemente :**
- Execution live (soumission ordres reels via API Binance)
- Scheduler / background tasks pour execution continue

**Endpoints a creer/adapter pour MVP (namespace `/bots`) :**

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

## Phase 11 — Performances & Backtesting (Page 3 MVP) — Partiel

> Ref : `v1_architecture_app_streamlit.pdf` — Page 3

### 11.1 — Backend endpoints — Partiel

**Existant :**
- `GET /trading/statistics` (PnL, win rate, nb trades — basique)
- `GET /trading/orders?status=filled` (journal trades filtrable)
- Modeles Order et Transaction avec timestamps, PnL

**Endpoints a creer pour MVP :**

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

### 11.4 — Algorithme d'intelligence artificielle (C12)

- Composant ML integre au projet (ex: prediction de prix, detection d'anomalies, recommandation de strategie)
- Choix du type de modele argumente (supervise, non supervise, renforcement)
- Framework : scikit-learn, TensorFlow ou PyTorch
- Evaluation sur echantillon test, pertinence metier justifiee
- Optimisation ressources (frugalite IA)
- Mesures d'optimisation du modele proposees

---

## Phase 12 — Admin, Monitoring & Alertes (Pages 5 + 6 MVP) — Partiel

> Ref : `v1_architecture_app_streamlit.pdf` — Pages 5 et 6

### 12.1 — Backend endpoints admin — Partiel

**Existant :**
- `GET /users/` (admin : liste tous les utilisateurs)
- `GET /users/{user_id}` (admin : fiche utilisateur)
- `PUT /users/{user_id}` (admin : modifier)
- `DELETE /users/{user_id}` (admin : supprimer)
- Endpoints activate/deactivate utilisateur

**Endpoints a creer/adapter pour MVP :**

| Methode | Endpoint | Description |
|---------|----------|-------------|
| GET | `/admin/users` | Liste utilisateurs (namespace admin dedie) |
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

## Livrables referentiel examen (transversal)

> Competences du referentiel Data Engineer (C1-C24) qui necessitent des livrables specifiques.
> Ref : `V2023_DE_Referentiel_v20231025.pdf`
>
> **Livrable livre** : `Cahier_des_charges_Crypto_Bot_V0.1.pdf` (22 pages, dec. 2024)

### Veille technologique et reglementaire (C2, C3) — Partiel

**Couvert par le CdC :**
- [x] Analyse concurrentielle (§7 — Cryptohopper, OctoBot, Freqtrade, etc.)
- [x] Tendances du marche (§7.3 — IA, convivialite, copie de trading)
- [x] Cadre reglementaire RGPD (§15 — conformite, conditions API Binance)

**A completer :**
- [ ] Rapport de veille formel : sources verifiees, canaux (RSS, alertes, reseaux pro)
- [ ] Cadre reglementaire complet : RGAA, RSE
- [ ] Synthese structuree avec identification des cas d'usage

### Cahier des charges formel (C4, C5) — Largement couvert

**Couvert par le CdC :**
- [x] Objectifs du projet (§1, §4 — 7 objectifs fonctionnels)
- [x] Besoins en architecture et sources de donnees (§9A, §10)
- [x] Contraintes (volume, delais — §19 calendrier)
- [x] Specifications fonctionnelles detaillees (§9 A-F — collecte, ETL, ML, trading, monitoring)
- [x] Specifications techniques (§10 — Python, FastAPI, PostgreSQL, Airflow, Docker)
- [x] Analyse SWOT (§8 — forces/faiblesses/opportunites/menaces)
- [x] Recommandations argumentees (§10 — choix technos, §7.4 — politiques tarifaires)
- [x] Conformite RGPD (§15)
- [x] Cas d'utilisation (Annexes — 8 cas avec diagrammes)
- [x] Livrables identifies (§17 — plateforme, dashboards, gestion users, documentation)

**A completer :**
- [ ] RGAA explicite (accessibilite)
- [ ] Eco-conception et impact ecologique estime
- [ ] Conception universelle

### Eco-conception et impact ecologique (C4, C8, C23) — A faire

> Non couvert par le CdC.

- [ ] Estimation empreinte de la solution (consommation K8s, stockage, reseau)
- [ ] Mesures de sobriete numerique proposees
- [ ] Cycle de vie des ressources (creation/retrait/archivage)
- [ ] Impact ecologique mesure des procedures ETL

### Accessibilite RGAA (C3, C4, C19, C20, C24) — A faire

> Non couvert par le CdC.

- [ ] Audit accessibilite du frontend Streamlit
- [ ] Conception universelle (utilisateurs + parties prenantes)
- [ ] Mesures d'inclusion personnes en situation de handicap dans l'equipe projet

### Gestion de projet formelle (C19, C20) — Partiel

**Couvert par le CdC :**
- [x] Outils de gestion identifies (§18 — Trello, Github, Drive, Slack)
- [x] Calendrier de developpement (§19 — 6 phases, soutenance sept. 2026)

**A completer :**
- [ ] Objectifs SMART (Specifique, Mesurable, Acceptable, Realiste, Temporel)
- [ ] Matrice RACI (roles et responsabilites)
- [ ] Methodes agiles documentees et justifiees (Kanban GitLab)

### Budget previsionnel (C21) — Partiel

**Couvert par le CdC :**
- [x] Chiffrage detaille (§21 — 6 426 EUR total)
- [x] Couts dev (frontend 160h, data engineer 200h, data scientist 120h = 5 760 EUR)
- [x] Couts infra (AWS Lightsail + t2.micro = 150 EUR)
- [x] Frais operationnels (transactions + API = 512 EUR)

**A completer :**
- [ ] Mise a jour budget avec infra reelle (Proxmox, domaine, licences)
- [ ] Analyse ecarts budget previsionnel vs charges reelles
- [ ] Mesures correctives si ecarts

### KPI et amelioration continue (C23) — A faire

> Non couvert par le CdC.

- [ ] Metriques quantifiables (avancement, couverture tests, uptime, latence)
- [ ] Mesure impact environnemental de la solution
- [ ] Feedback utilisateurs pris en compte
- [ ] Axes d'amelioration SMART argumentes

### Plan d'accompagnement utilisateurs (C24) — Partiel

**Couvert par le CdC :**
- [x] Typologies d'utilisateurs (§5 — 3 personas : Occasionnel, Experimente, Debutant)
- [x] Besoins par profil identifies (interface simple, outils avances, mode educatif)

**A completer :**
- [ ] Plan de formation structure (sequencement, sujets)
- [ ] Support prise en main de la solution

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
