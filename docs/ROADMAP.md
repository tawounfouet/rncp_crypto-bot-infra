# Roadmap Crypto-Bot

> Historique et vue d'ensemble du projet. Le suivi vivant (taches en cours,
> backlog detaille, priorites) se fait sur GitLab, pas ici :
>
> - Issues : [crypto-bot-app](https://gitlab.com/dst_crypto/crypto-bot-app/-/issues)
> - Board Kanban et Milestones : voir [GESTION_PROJET.md](GESTION_PROJET.md) §4
>
> Ce document ne liste que ce qui est **termine** (valeur de preuve pour la
> soutenance) et le mapping avec le referentiel d'examen. Spec MVP :
> `v1_architecture_app_streamlit.pdf`.

---

## Vue d'ensemble

### Infrastructure

| Phase | Description | Statut |
|-------|-------------|--------|
| 1 — Cluster & Infrastructure | Talos sur Proxmox, MetalLB, Ingress, storage | Done |
| 2 — Deploiements & GitOps | Kustomize + Sealed Secrets + ArgoCD (3 envs) | Done |
| 3 — CI/CD | Pipeline GitLab CI, sync bidirectionnel Git | Done |
| 4 — Monitoring & Outillage | Loki/Promtail/Grafana, GitLab Runner self-hosted | Done |
| 5 — Acces & Resilience | Cloudflare Tunnel, backups + fallback VM AWS | Plan pret |

### Fonctionnel

> Detail des taches (endpoints, pages, criteres d'acceptation) : voir les
> issues et milestones GitLab correspondants.

| Phase | Description | Statut |
|-------|-------------|--------|
| 6 — Qualite & Tests | Tests unitaires backend/frontend, tests d'integration, logging | Partiel |
| 7 — Fondations techniques | Architecture frontend, figeage versions, architecture donnees, ETL | Partiel |
| 8 — Securite Binance & RGPD | Chiffrement cles API, conformite RGPD | A faire |
| 9 — Portefeuille (Page 1) | Endpoints + frontend portfolio | Partiel |
| 10 — Bot & Trading (Pages 2+4) | Endpoints + frontend bots, strategies DCA/Grid | Partiel |
| 11 — Performances & Backtesting (Page 3) | Endpoints + frontend performance, backtesting, IA | Partiel |
| 12 — Admin, Monitoring & Alertes (Pages 5+6) | Endpoints admin, proxy Prometheus, dashboards | Partiel |
| 13 — Documentation utilisateur | Guide utilisation, guide Binance, FAQ | A faire |

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

- **2.1** : Kustomize (base + overlays dev/staging/production), Sealed Secrets controller v0.29.0, SealedSecrets 3 envs, ImagePullSecrets gitlab-registry, 5/5 pods par env
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

<details>
<summary>Rotation des acces suite a compromission d'un poste (17/07/2026)</summary>

- Revocation cle SSH Proxmox, regeneration kubeconfig/talosconfig
- Rotation secrets applicatifs (staging + production) : `POSTGRES_PWD`, `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY`, `SECRET_KEY`, `BINANCE_ENC_KEY`
- Script `scripts/rotate_secrets.sh` cree (modes staging/production/argocd/grafana, verification post-rotation automatisee)
- Rotation mots de passe ArgoCD + Grafana
- Renommage `overlays/prod` → `overlays/production` (coherence avec le namespace k8s)
- Correction fuite de mot de passe DB dans les logs backend (`shared/database/connection.py`)
- Procedure documentee dans `ONBOARDING.md` §9

</details>

---

## Hygiene technique (transversal)

- [ ] NetworkPolicies / RBAC (isolation namespaces) — enforcement (manifests deja deployes, policy controller manquant)
- [ ] Audit securite du code (injections, deps vulnerables)
- [x] minio:latest → version pinnee

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

Voir [GESTION_PROJET.md](GESTION_PROJET.md) pour le detail (RACI, SMART, Kanban, calendrier, budget).

### Budget previsionnel (C21) — Partiel

Voir [GESTION_PROJET.md](GESTION_PROJET.md) §8.

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
