# Gestion de Projet — Crypto-Bot

> Competences C19, C20 du referentiel Data Engineer.
> Ref : `V2023_DE_Referentiel_v20231025.pdf`

---

## 1. Contexte

- **Projet** : Crypto-Bot — Bot de trading automatise pour Binance
- **Formation** : Alternance Data Engineer, Liora / OMNES Education (sept. 2024)
- **Soutenance** : 1er septembre 2026
- **Cahier des charges** : `Cahier_des_charges_Crypto_Bot_V0.1.pdf` (dec. 2024)

---

## 2. Equipe et matrice RACI

### Membres

| Nom | Role principal |
|-----|---------------|
| Nathalie AVRIL | Infrastructure, DevOps, Backend, Frontend |
| Bangali DIOUBATE | <!-- TODO : preciser --> |
| Lo BARET | <!-- TODO : preciser --> |
| Thomas AWOUNFOUET | <!-- TODO : preciser --> |

### Matrice RACI

> **R** = Responsable (realise), **A** = Approbateur (valide), **C** = Consulte, **I** = Informe

| Livrable / Phase | Nathalie | Bangali | Lo | Thomas |
|------------------|----------|---------|-----|--------|
| Cahier des charges | R | R | R | R |
| Infrastructure K8s (Phases 1-5) | R/A | I | I | I |
| Backend API (FastAPI) | <!-- TODO --> | <!-- TODO --> | <!-- TODO --> | <!-- TODO --> |
| Frontend (Streamlit) | <!-- TODO --> | <!-- TODO --> | <!-- TODO --> | <!-- TODO --> |
| Pipeline ETL (C11) | <!-- TODO --> | <!-- TODO --> | <!-- TODO --> | <!-- TODO --> |
| Composant IA / ML (C12) | <!-- TODO --> | <!-- TODO --> | <!-- TODO --> | <!-- TODO --> |
| Tests et qualite | <!-- TODO --> | <!-- TODO --> | <!-- TODO --> | <!-- TODO --> |
| Documentation | R | R | R | R |
| Veille technologique | <!-- TODO --> | <!-- TODO --> | <!-- TODO --> | <!-- TODO --> |

> A completer avec la repartition reelle des responsabilites.

---

## 3. Objectifs SMART

> Reformulation des objectifs du cahier des charges au format SMART.

### O1 — Application de trading fonctionnelle

| Critere | Description |
|---------|-------------|
| **S** — Specifique | Application web (Streamlit + FastAPI) connectee a l'API Binance, permettant de visualiser un portefeuille, configurer et executer des bots de trading |
| **M** — Mesurable | 6 pages fonctionnelles (Portefeuille, Controle Bot, Performances, Parametrage, Admin, Monitoring), 50+ endpoints API, 2 strategies minimum (DCA, Grid Trading) |
| **A** — Acceptable | Valide par l'equipe et le jury Liora, conforme au cahier des charges V0.1 |
| **R** — Realiste | Equipe de 4 personnes, stack Python maitrisee, API Binance documentee, infra K8s operationnelle |
| **T** — Temporel | MVP fonctionnel avant juillet 2026, soutenance 1er septembre 2026 |

### O2 — Infrastructure Cloud / On-Premise

| Critere | Description |
|---------|-------------|
| **S** — Specifique | Cluster Kubernetes (Talos) sur Proxmox avec CI/CD GitOps (ArgoCD), 3 environnements (dev, staging, production), monitoring (Grafana/Loki), fallback AWS |
| **M** — Mesurable | 5/5 pods par env, CI pipeline < 5min, ArgoCD sync < 2min, uptime staging > 95% |
| **A** — Acceptable | Architecture validee (ARCHITECTURE.md), deployable par tout membre de l'equipe (ONBOARDING.md) |
| **R** — Realiste | Proxmox disponible, Tailscale configure, VM AWS de backup, runner self-hosted operationnel |
| **T** — Temporel | Phases 1-4 livrees (fev. 2026), phases 5 (acces + backups) avant avril 2026 |

### O3 — Pipeline de donnees et composant IA

| Critere | Description |
|---------|-------------|
| **S** — Specifique | Pipeline ETL automatise (collecte Binance → transformation → stockage PostgreSQL) + composant ML (prediction ou recommandation strategie) |
| **M** — Mesurable | Collecte multi-crypto fonctionnelle, indicateurs techniques calcules (SMA, RSI, MACD, BB), modele ML evalue (metriques sur echantillon test) |
| **A** — Acceptable | Pipeline documente, modele justifie (choix argumente), conformite eco-conception |
| **R** — Realiste | Donnees Binance accessibles gratuitement, frameworks ML maitrisables (scikit-learn, TensorFlow) |
| **T** — Temporel | ETL automatise avant mai 2026, composant IA avant juin 2026 |

### O4 — Conformite et documentation

| Critere | Description |
|---------|-------------|
| **S** — Specifique | Conformite RGPD (chiffrement cles API, consentement, droit suppression), accessibilite RGAA, documentation technique et utilisateur complete |
| **M** — Mesurable | Audit RGAA realise, guide utilisateur redige, chiffrement AES-256-GCM en BDD, journalisation des acces |
| **A** — Acceptable | Conforme aux exigences du referentiel (C1-C24), valide par le jury |
| **R** — Realiste | Streamlit offre un controle limite sur l'accessibilite (compromis documente) |
| **T** — Temporel | Documentation continue, livrables referentiel finalises avant aout 2026 |

---

## 4. Methodologie agile — Kanban

### Choix de la methode

Le projet utilise **Kanban** plutot que Scrum pour les raisons suivantes :
- Equipe en alternance (disponibilite variable, pas de sprints fixes)
- Flux continu de taches avec priorites changeantes
- Visualisation simple de l'avancement via le board GitLab
- Pas de ceremonies formelles requises (standup, retro) — remplacees par les points mensuels

### Board GitLab

Le board Kanban est configure sur le repo [crypto-bot](https://gitlab.com/dst_crypto/crypto-bot/-/boards) avec les colonnes :

| Colonne | Description |
|---------|-------------|
| **Open** | Issues creees, pas encore prises en charge |
| **In Progress** | En cours de realisation |
| **Closed** | Terminee et validee |

### Labels

| Label | Usage |
|-------|-------|
| `phase::N` | Phase de la roadmap (5-13) |
| `type::feature` | Fonctionnalite |
| `type::infra` | Infrastructure |
| `type::docs` | Documentation |
| `type::bug` | Correction de bug |
| `type::ci` | Pipeline CI/CD |
| `sub::backend` | Concerne le backend |
| `sub::frontend` | Concerne le frontend |
| `status::partiel` | Implementation commencee, a completer |
| `referentiel` | Livrable du referentiel examen |

### Milestones

Les milestones regroupent les issues par livrable. Ils permettent de suivre l'avancement global par objectif.

| Milestone | Competences | Issues |
|-----------|------------|--------|
| Soutenance v1.0 | Transversal | Infra, tests, fondations, hygiene |
| Cahier des charges | C4, C5 | #53 |
| Veille technologique | C2, C3 | #52 |
| Pipeline ETL | C11 | #50 |
| Composant IA | C12 | #51 |
| Visualisation donnees | C10 | #49 |
| Eco-conception | C4, C8, C23 | #54 |
| Accessibilite RGAA | C3, C24 | #55 |
| Gestion de projet | C19, C20 | #56 |
| Budget previsionnel | C21 | #57 |
| KPI amelioration | C23 | #58 |
| Accompagnement utilisateurs | C24 | #59 |
| MVP Fonctionnel | Phases 8-12 | #24-43 (20 issues) |
| Documentation utilisateur | Phase 13 | #44-46 |

> Vue d'ensemble : [Milestones du groupe dst_crypto](https://gitlab.com/groups/dst_crypto/-/milestones)

---

## 5. Outils de suivi

| Outil | Usage |
|-------|-------|
| **GitLab Issues** | Suivi des taches, assignation, labels, milestones |
| **GitLab Board** | Vue Kanban de l'avancement |
| **GitLab Milestones** | Regroupement par livrable, % avancement |
| **GitLab CI/CD** | Pipelines automatises (lint, test, build, deploy) |
| **ArgoCD** | GitOps — deploiement continu K8s |
| **Grafana** | Monitoring applicatif et logs |
| **Google Drive** | Edition collaborative (CR de reunions, brouillons) |

---

## 6. Points mensuels et comptes-rendus

### Organisation

- **Frequence** : 1 point par mois (equipe projet)
- **Format** : Visio ou presentiel, duree ~1h
- **Ordre du jour type** :
  1. Tour de table — avancement individuel
  2. Revue des milestones et issues GitLab
  3. Blocages et decisions a prendre
  4. Objectifs pour le mois suivant
  5. Questions diverses

### Comptes-rendus

Les comptes-rendus (CR) sont rediges sur Google Drive pendant la reunion, puis commites dans le repo pour tracabilite :

```
crypto-bot-infra/docs/cr/
  CR_2024-10.md
  CR_2024-11.md
  CR_2024-12.md
  CR_2025-01.md
  ...
```

**Contenu type d'un CR :**

```markdown
# Compte-rendu — Mois AAAA-MM

**Date** : JJ/MM/AAAA
**Presents** : Nathalie, Bangali, Lo, Thomas
**Absents** : —

## Avancement
- [resume par personne ou par milestone]

## Decisions prises
- [decisions]

## Blocages identifies
- [blocages]

## Objectifs mois suivant
- [objectifs]
```

> Les CR existants sur le Drive seront migres progressivement dans `docs/cr/`.

---

## 7. Calendrier macro

> Ref : Cahier des charges §19

| Periode | Phase | Statut |
|---------|-------|--------|
| Oct. 2024 — Dec. 2024 | Conception, cahier des charges, collecte donnees | Done |
| Jan. 2025 — Fev. 2025 | Infrastructure K8s, CI/CD, monitoring | Done |
| Mars 2025 — Mai 2025 | Fondations techniques, securite, ETL | En cours |
| Juin 2025 — Aout 2025 | MVP fonctionnel (pages 1-6), composant IA | A faire |
| Sept. 2025 — Dec. 2025 | Tests, backtesting, ameliorations | A faire |
| Jan. 2026 — Avril 2026 | Documentation, accessibilite, eco-conception | A faire |
| Mai 2026 — Juillet 2026 | Finalisation, livrables referentiel | A faire |
| Aout 2026 | Preparation soutenance | A faire |
| **1er sept. 2026** | **Soutenance** | |

---

## 8. Budget

> Detail dans le Cahier des charges §21. Analyse des ecarts a realiser en fin de projet.

| Categorie | Previsionnel (CdC) | Reel | Ecart |
|-----------|-------------------|------|-------|
| Developpement (480h) | 5 760 EUR | <!-- TODO --> | — |
| Infrastructure (AWS) | 150 EUR | <!-- TODO : + Proxmox, Tailscale, domaine --> | — |
| Frais operationnels | 512 EUR | <!-- TODO --> | — |
| **Total** | **6 426 EUR** | <!-- TODO --> | — |

> L'analyse des ecarts et les mesures correctives seront documentees ici en phase de finalisation.
