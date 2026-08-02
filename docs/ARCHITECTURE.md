# Architecture Crypto-Bot

## 1. Contexte et objectifs

### Situation actuelle

- Backend FastAPI (:8009) + Frontend Streamlit (:8501)
- BDD : PostgreSQL 14, MinIO (S3-compatible)
- Infra : cluster Kubernetes (Talos) sur le serveur Proxmox — staging et
  production tournent en namespaces separes, deployees via GitOps ArgoCD
  (voir §5)
- CI/CD : GitLab CI (lint > test > build > update:manifests → ArgoCD sync)
- VM AWS Liora : reverse proxy + backups off-site + fallback
  docker-compose (bascule uniquement si le Proxmox tombe, voir §5)
- Registry : GitLab Container Registry (`registry.gitlab.com/dst_crypto/crypto-bot-app`)

> **Avant la migration K8s** (contexte historique) : l'application tournait
> entierement en Docker Compose sur la VM AWS, staging (:8009/:8501) et
> production (:9009/:8502) sur la meme machine, deploiement CI via SSH.
> C'est ce constat de depart (VM unique, pas de redondance, SSH deploy) qui
> a motive l'analyse comparative ci-dessous.

### Materiel disponible

| Ressource | Specs | Role |
|-----------|-------|------|
| **Serveur Proxmox (P1)** | 64 GB RAM, 512 GB SSD | Cluster K8s complet |
| VM AWS Liora | 2 vCPU, 7.6 GB RAM, 29 GB | Reverse proxy + fallback |
| Dell Inspiron 5515 | 16 GB RAM | Dev local |

### Contraintes

| Contrainte | Impact |
|------------|--------|
| Proxmox derriere le NAT de la box internet | Pas d'IP publique → tunnel outbound-only (Tailscale) |
| VM AWS : 8.9 GB disque libre | Role minimal : reverse proxy + backups |
| Equipe projet | Doivent acceder a l'app via Cloudflare Tunnel |

### Objectifs

1. **Redondance** : cluster K8s 3 noeuds + fallback docker-compose sur VM AWS
2. **Competences K8s/Talos** : montrer une maitrise Kubernetes en soutenance
3. **GitOps** : pipeline CI/CD moderne avec ArgoCD (staging auto, prod manuelle)
4. **Disponibilite equipe** : acces via Cloudflare Tunnel + fallback VM AWS
5. **Optimisation des couts** : ~7 EUR/mois vs ~283 EUR/mois full cloud (97.5% economie)
6. **Reproductibilite** : infra entierement reconstruisible depuis Git (GitOps)
7. **Securisation** : bridge isole, RBAC, Sealed Secrets, zero port entrant

---

## 2. Analyse comparative des architectures

Trois approches ont ete evaluees avant de choisir l'architecture finale.

### Option A : Tout sur PC perso (proposition initiale)

```
VM AWS = simple fallback docker-compose (inchangee)
PC     = cluster Talos (1 CP + 2 workers), staging + prod en namespaces
```

| Avantage | Inconvenient |
|----------|-------------|
| Simple a mettre en place | PC eteint = cluster K8s inaccessible |
| Pas de probleme reseau | VM AWS sous-utilisee |
| Tout en local | Equipe ne peut pas acceder au cluster |

### Option B : VM AWS comme control plane CI/CD

```
VM AWS = GitLab Runner + ArgoCD (dans Docker)
PC     = 2 clusters Talos separes (staging + prod)
```

| Avantage | Inconvenient |
|----------|-------------|
| VM AWS valorisee | Necessite sudo/root (PAS DISPO) |
| 2 clusters = impressionnant | ArgoCD sur VM doit joindre le PC derriere NAT |
| | `argocd app sync` = push model, PAS du vrai GitOps |

**Vrai GitOps (pull) vs faux GitOps (push) :**

```
PUSH : CI execute "argocd app sync" → deploie
       Si le CI est casse, on ne peut plus deployer.
       Git n'est pas la source de verite.

PULL (notre choix) : CI commit un tag image dans le repo infra
                     ArgoCD surveille le repo en permanence
                     ArgoCD detecte le changement et sync tout seul
                     Git EST la source de verite
```

### Option C retenue : Architecture hybride on-premise + cloud

```
Serveur Proxmox (64 GB)  → Cluster Talos K8s complet (staging + prod)
VM AWS (7.6 GB)           → Reverse proxy + backups off-site + fallback docker-compose
```

L'equipe accede a l'app via Cloudflare Tunnel (outbound-only depuis le Proxmox).
Si le Proxmox tombe, la VM AWS bascule automatiquement sur docker-compose
avec les derniers backups DB (max 6h de retard).

Grace au GitOps, le cluster est recree en 30 minutes depuis Git.
Cout total : ~7 EUR/mois vs ~283 EUR/mois en full cloud AWS.

---

## 3. Hardware et budget

### VMs sur Proxmox

| VM | Role | vCPU | RAM | Disque |
|----|------|------|-----|--------|
| talos-cp1 | Control Plane + etcd | 4 | 8 GB | 60 GB |
| talos-worker1 | Worker (staging) | 6 | 20 GB | 150 GB |
| talos-worker2 | Worker (prod) | 6 | 20 GB | 150 GB |

Budget RAM : 52 GB alloues sur 64 GB (~12 GB spare).

### Comparatif des couts

```
FULL CLOUD AWS                    ARCHITECTURE HYBRIDE (notre choix)
─────────────                     ──────────────────────────────────
EKS control plane    ~73 EUR      Serveur Proxmox      0 EUR (amorti)
3x EC2 t3.medium     ~90 EUR      Electricite serveur   ~3 EUR
RDS PostgreSQL       ~30 EUR      VM AWS minimale       ~4 EUR
DocumentDB           ~60 EUR      Cloudflare Tunnel     0 EUR (free tier)
ALB                  ~20 EUR      Tailscale             0 EUR (free tier)
EBS 100 GB           ~10 EUR
─────────────────────────         ──────────────────────────────────
Total : ~283 EUR/mois             Total : ~7 EUR/mois
        ~3 400 EUR/an                     ~84 EUR/an
                                  Economie : 97.5%
```

---

## 4. Securisation et acces

### Isolation reseau

```
Reseau domestique (LAN)
    │
    ├── Proxmox host (interface management, vmbr0)
    │
    └── Bridge isole K8s (vmbr1) ← AUCUN acces au LAN
         ├── VM talos-cp1      (8 GB)
         ├── VM talos-worker1  (20 GB)
         └── VM talos-worker2  (20 GB)
              │
              └── Tunnel sortant uniquement → VM AWS / Cloudflare
```

- VMs K8s sur un bridge dedie (`vmbr1`), **isole du reste du LAN**
- **Zero port entrant** sur la box internet
- Tunnel outbound-only (Cloudflare Tunnel ou WireGuard)

### Controle d'acces par couche

| Couche | Mecanisme |
|--------|-----------|
| Proxmox host | SSH par cle uniquement |
| Kubernetes API | RBAC : roles par namespace |
| ArgoCD | Authentification + roles |
| Secrets | Sealed Secrets : chiffres dans Git |
| Containers | Execution non-root |
| Images | Pull depuis GitLab Registry (prive) |
| Bases de donnees | ClusterIP uniquement (jamais exposees) |

### Acces equipe vs admin

| | Equipe (devs) | Admins (ops) |
|--|---------------|--------------|
| Via | Cloudflare Tunnel | Tailscale VPN |
| Installe | Rien (navigateur) | Tailscale client |
| Acces | App staging/prod | kubectl, ArgoCD, Grafana |

---

## 5. Architecture cible

### Vue globale — Flux GitOps

```mermaid
flowchart TB
    DEV[Developpeur] -->|git push| CI["crypto-bot-app CI\ntest → build → push images"]
    CI -->|"images :staging / :vX.Y.Z"| REG[(GitLab Registry)]

    CI -->|"deploy:staging (auto)\ndeploy:production (manuel)"| VMAWS["VM AWS\ndocker-compose\nstaging + production"]
    CI -->|"update:manifests\ncommit annotation"| INFRA["crypto-bot-infra/main"]

    INFRA --> ARGOCD{ArgoCD}
    ARGOCD -->|auto-sync| K8S_STAGING["K8s staging"]
    ARGOCD -->|sync manuel| K8S_PROD["K8s production"]

    REG -.->|pull image| K8S_STAGING
    REG -.->|pull image| K8S_PROD

    K8S_STAGING --> LOGS["Loki + Promtail + Grafana"]
    K8S_PROD --> LOGS

    style K8S_STAGING fill:#c3fae8,stroke:#087f5b
    style K8S_PROD fill:#ffe3e3,stroke:#e03131
    style VMAWS fill:#fff3bf,stroke:#e67700
```

> Le cluster K8s (via ArgoCD, GitOps pull-based) est la cible principale.
> La VM AWS recoit un deploiement direct (SSH) a chaque release, ce qui la
> maintient a jour en permanence pour servir de bascule immediate si le
> Proxmox tombe (voir mecanisme de fallback ci-dessous).

### Architecture applicative

```mermaid
flowchart TB
    USER[Utilisateur] --> ING["Ingress NGINX\n/ → frontend, /api → backend"]
    ING --> FE["Frontend\nStreamlit :8501"]
    ING --> BE["Backend\nFastAPI :8009"]

    FE -->|API call| BE

    subgraph ROUTERS["API Routers"]
        R1["/v1/auth"]
        R2["/v1/trading"]
        R3["/v1/market"]
    end
    BE --> ROUTERS

    subgraph SERVICES["Services metier"]
        S1[AuthService]
        S2[TradingService]
        S3[BacktestEngine]
    end
    ROUTERS --> SERVICES

    subgraph STRATEGIES["Strategies"]
        ST1["Moving Average"]
        ST2["RSI / Bollinger"]
    end
    SERVICES --> STRATEGIES

    BE --> PG[("PostgreSQL 14\n:5432 — 5Gi")]
    BE --> MINIO[("MinIO\n:9000 — 10Gi")]
    BE -->|API call| BINANCE["Binance API\n(externe)"]
```

### Infrastructure Kubernetes

```mermaid
flowchart TB
    subgraph NET["Reseau"]
        TS["Tailscale\nsubnet routing"]
        BR["vmbr1\n10.10.0.0/24"]
    end

    subgraph PROXMOX["Proxmox VE — Cluster Talos K8s"]
        CP["Control Plane\n10.10.0.125:6443"]
        W1["Worker 1\n10.10.0.112"]
        W2["Worker 2\n10.10.0.163"]
    end
    NET --> PROXMOX

    subgraph K8SINFRA["Couche infrastructure K8s"]
        MLB["MetalLB\nL2 .240-.250"]
        NGINX["Ingress NGINX\n.240"]
        LPP["local-path\nprovisioner"]
        SS["Sealed Secrets\nv0.29.0"]
        ARGO["ArgoCD\nv3.3.2"]
    end
    PROXMOX --> K8SINFRA

    subgraph NAMESPACES["Namespaces applicatifs"]
        DEVNS["dev\nbackend frontend postgres minio"]
        STGNS["staging (auto-sync)\nbackend frontend postgres minio"]
        PRODNS["production (manuel)\nbackend frontend postgres minio"]
    end
    K8SINFRA --> NAMESPACES

    subgraph MON["Monitoring — ns: monitoring (ArgoCD GitOps)"]
        PROM["Promtail (3x DaemonSet)"]
        LOKI["Loki — PVC 5Gi"]
        GRAF["Grafana 10.3.3 — :3000"]
    end
    NAMESPACES --> MON

    style STGNS fill:#c3fae8,stroke:#087f5b
    style PRODNS fill:#ffe3e3,stroke:#e03131
```

### Mecanisme de fallback

```
FONCTIONNEMENT NORMAL :
  Utilisateur → VM AWS (Nginx) → Tunnel → K8s (Proxmox)

SI LE PROXMOX TOMBE :
  1. Nginx detecte le tunnel mort (health check)
  2. Restauration des derniers backups DB (max 6h)
  3. docker-compose up sur la VM AWS
  4. Nginx bascule vers localhost
  → L'application est de nouveau accessible en ~2 min

RETOUR A LA NORMALE :
  1. Proxmox redmarre, tunnel se retablit
  2. Nginx re-bascule vers le cluster K8s
  3. docker-compose down sur la VM AWS

GARANTIES :
  RPO (perte de donnees max) : 6h (intervalle configurable)
  RTO (temps de bascule)     : ~2 min (manuel) / ~30s (automatise)
```

### GitOps avec ArgoCD

Le deploiement suit un modele **pull-based** (vrai GitOps) : le CI ne deploie jamais directement sur le cluster. Git est la source de verite.

```
PUSH sur staging
  → GitLab CI : test → build:docker → update:manifests
    → Commit "ci(gitops): staging rollout <sha>" dans crypto-bot-infra/main
    → ArgoCD detecte le changement (polling 3 min)
    → Auto-sync → rolling update backend + frontend

TAG vX.X
  → GitLab CI : test → build:docker → update:manifests
    → Commit "ci(gitops): production vX.X (<sha>)" dans crypto-bot-infra/main
    → ArgoCD affiche OutOfSync
    → Sync manuel → rolling update
```

**Mecanisme** : le tag image staging est fixe (`:staging`), donc un simple push d'image ne produit aucun diff dans les manifests. Le job `update:manifests` ajoute une annotation `deployed-commit: "<sha>"` dans le pod template. Ce changement est detecte par ArgoCD et declenche un rolling update.

| Application ArgoCD | Namespace | Sync | Strategie |
|-------------------|-----------|------|-----------|
| `crypto-bot-staging` | staging | **Auto-sync** + prune + selfHeal | Chaque commit CI declenche un rollout |
| `crypto-bot-production` | production | **Manuel** | Review avant sync, tag versionne |
| `monitoring` | monitoring | **Auto-sync** | Helm loki-stack + dashboards Grafana |

Le namespace `dev` n'est pas gere par ArgoCD — deploiement manuel via `dev-deploy.sh`.

### Choix technologiques

| Composant | Choix | Justification |
|-----------|-------|---------------|
| OS K8s | **Talos Linux** | Immutable, securise, API-driven, pas de SSH |
| Hyperviseur | **Proxmox VE** | Interface web, snapshots, KVM natif |
| Overlay network | **Flannel** (defaut Talos) | Simple, integre a Talos. **Ne supporte pas les NetworkPolicies** sans policy controller additionnel (Calico, Kube-Router). Les manifests NetworkPolicy sont deployes (intention documentee) mais non enforces tant qu'un policy controller n'est pas installe. |
| LoadBalancer | **MetalLB** | IPs LoadBalancer sur bare-metal |
| Ingress | **NGINX Ingress Controller** | Standard, bien documente |
| GitOps | **ArgoCD** | Reference GitOps pull-based, UI web |
| Manifests | **Kustomize** | Natif kubectl, base + overlays |
| Storage | **local-path-provisioner** | PVs sur disque local des workers |
| Secrets | **Sealed Secrets** | Chiffres dans Git, dechiffres dans le cluster |
| Monitoring | **Loki + Promtail + Grafana** | Logs centralises (Helm chart loki-stack v2.10.3) |
| Acces equipe | **Cloudflare Tunnel** | Outbound-only, zero port entrant, free tier |
| Acces admin | **Tailscale** | Mesh VPN gratuit, traverse NAT |
| VM AWS | **Nginx + docker-compose** | Reverse proxy + resilience |
| Backups | **CronJob K8s** | pg_dump toutes les 6h vers VM AWS |

### Pourquoi 3 VMs Talos sur 1 seul serveur physique

```
1 serveur physique + Talos bare-metal = 1 seul noeud Kubernetes

Mais on veut 3 noeuds (1 CP + 2 workers) sur 1 machine.
→ Proxmox cree 3 VMs, chaque VM boot sur Talos ISO.
→ Chaque VM = un noeud K8s independant.
```

Proxmox agit comme hyperviseur : chaque VM Talos est un noeud K8s a part
entiere (isolation memoire/CPU/disque via KVM), ce qui permet de simuler un
vrai cluster multi-noeuds sur un seul serveur.

---

## 6. Points de soutenance

### Narrative recommandee

> "Nous avons une architecture hybride on-premise + cloud :
> - Un cluster Kubernetes Talos OS sur un serveur Proxmox heberge
>   staging et production avec un workflow GitOps ArgoCD.
> - Une VM AWS sert de point d'entree (reverse proxy) et de filet
>   de securite : en cas de panne du serveur, un fallback docker-compose
>   prend le relais avec les derniers backups (RPO 6h, RTO 2 min).
> - L'equipe accede a l'application via Cloudflare Tunnel, sans aucun
>   port ouvert sur la box internet.
> - L'infrastructure est entierement reproductible depuis Git : on peut
>   recreer le cluster en 30 minutes, ArgoCD redeploie tout (voir INSTALL.md).
> - Cette architecture offre la meme resilience qu'un full cloud AWS
>   pour 97.5% moins cher (~7 EUR/mois vs ~283 EUR/mois)."

### Points techniques a mettre en avant

1. **Talos OS** : OS immutable, pas de SSH, gestion 100% API = securite renforcee
2. **GitOps pull-based** : ArgoCD surveille Git et reconcilie (pas de push depuis le CI)
3. **Kustomize** : meme base de manifests, overlays par environnement
4. **Architecture hybride** : K8s on-premise + cloud minimal (reverse proxy + backups)
5. **Fallback automatise** : docker-compose sur VM AWS avec backups toutes les 6h
6. **Infra reproductible** : cluster jetable, Git est la source de verite
7. **Resilience** : 2 workers K8s, pods reschedulables, fallback cloud
8. **Securisation** : bridge isole, RBAC, Sealed Secrets, Cloudflare Tunnel, zero port entrant
9. **Monitoring** : Loki + Promtail + Grafana pour les logs centralises de tous les pods
10. **Optimisation des couts** : 97.5% d'economie vs full cloud AWS

## 7. Pistes ouvertes (non tranchees)

### k3s sur la VM Liora, pour unifier docker-compose et manifests K8s

**Constat (2026-07-22/23)** : la VM Liora et le cluster K8s Proxmox sont deux mecanismes
de deploiement independants, avec deux definitions separees de "quels services existent".
`docker-compose.staging.yml`/`.prod.yml` (VM) et `base/kustomization.yaml` (K8s) ont deja
diverge concretement : Airflow et MLflow tournent sur la VM mais n'ont aucun manifest K8s
equivalent (cf. `docs/SECRETS_ET_TOKENS.md`, section asymetrie).

**Piste** : installer k3s sur la VM et lui appliquer les memes manifests
(`base/` + `overlays/`) que sur Talos, au lieu de maintenir `docker-compose.*.yml` en
parallele. k3s est une distribution Kubernetes certifiee conforme (CNCF) — memes
`apiVersion`/`kind`, `kubectl apply -k` identique, pas de dialecte a adapter.

**Point de blocage identifie, puis CONFIRME EN INCIDENT REEL le 2026-07-24** : la VM Liora
a 7,6 Go de RAM, **sans swap**. Etat mesure le 2026-07-23 (staging seul, hors charge
Airflow reelle) : 6,4 Gi disponibles. Le 2026-07-24, au premier `deploy:production`
(staging + production tournant simultanement, chacun avec son Airflow/mlflow/backend/
frontend/postgres/minio), la VM est devenue **totalement inaccessible en SSH**
("Connection timed out during banner exchange", reproduit aussi depuis un acces direct
hors session utilisateur) — `sshd` lui-meme ne repondait plus, signe de pression memoire
severe (sans swap, pas de degradation progressive). RAM disponible mesuree juste apres
retour d'acces : **285-364 Mi seulement** sur 7,6 Gi. Resolu par `docker compose -f
docker-compose.prod.yml down` (staging seul suffit a occuper ~4 Gi/7,6 Go) ; disponible
remonte a 3,3 Gi immediatement apres. **staging + production ne rentrent pas ensemble sur
cette VM, point.** Ce n'est plus une hypothese depuis un dev comparable — c'est reproduit
en conditions reelles sur la VM elle-meme. Ajouter le control-plane k3s (apiserver +
controller-manager + scheduler + kubelet + containerd, ~1-1,5 Go meme en config minimale
single-node) par-dessus serait encore pire.

**Decision immediate prise (2026-07-24)** : ne plus jamais lancer `docker-compose.prod.yml`
et `docker-compose.staging.yml` simultanement sur cette VM tant qu'aucune des pistes
ci-dessous n'est implementee. `production` reste coupe (`down`) apres l'incident, a
reprendre uniquement apres decision sur la repartition.

**Baseline RAM mesuree le 2026-07-24 (rien ne tourne)** : 382 Mi utilises, 7,0 Gi
disponibles sur 7,6 Gi. Recoupe avec la mesure "staging seul" (~4 Gi utilises) : un
environnement complet (backend+frontend+postgres+minio+mlflow+airflow) consomme
**~3,6-4 Gi**. Deux environnements necessiteraient donc ~7,2-8 Gi — au-dela ou a la limite
stricte des 7,6 Gi disponibles, sans marge pour les pics (builds, imports Airflow, etc.) et
sans swap pour absorber un depassement. Confirme numeriquement que staging+production ne
rentrent pas ensemble, pas seulement par l'incident.

**A faire avant de trancher** : chiffrer le besoin RAM reel (somme des `requests` des
manifests K8s existants + futurs mlflow/airflow) plutot que d'extrapoler. La VM tournant
sur le Proxmox perso (pas l'AWS de l'ecole), augmenter sa RAM allouee reste possible
(`qm set --memory`) si le host a la marge — a verifier cote `pve1`.

### Alternative a Airflow : dlt (data load tool) + cron, pour reduire l'empreinte

**Constat** : le cout memoire d'Airflow n'est pas la logique des taches elles-memes
(`jobs/ingest/collect_ohlcv.py`, `jobs/transform/load_ohlcv.py`), mais le **webserver +
scheduler + base Postgres dediee**, qui tournent en permanence meme sans tache active.

**Piste** : remplacer la logique de collecte/chargement par `dlt` (librairie Python
extraction/chargement, pas un orchestrateur — pas de scheduler ni d'UI propre), declenchee
par un simple `cron` (VM) ou `CronJob` Kubernetes (si k3s/Talos). Ca supprime entierement
le trio webserver+scheduler+DB dediee d'Airflow, cout memoire bien plus significatif que
d'optimiser Airflow lui-meme.

**Point d'attention avant de trancher** : plusieurs issues du groupe `crypto-bot` (le repo
academique) portent le label `sub::orchestration` (#60, #61) ou mentionnent explicitement
Airflow (#73 — "Scalabilite orchestrateur : Airflow LocalExecutor → Celery/
KubernetesExecutor"). Si le cahier des charges/la grille de soutenance evalue une
competence "orchestration avec Airflow" specifiquement, remplacer par cron+dlt pourrait
jouer contre la notation malgre le gain en ressources — **a verifier avant toute
implementation**, cette piste n'est pas purement technique.

### Airflow sur le cluster K8s (Proxmox) plutot que sur la VM Liora

**Constat** : le Proxmox a 64 Go de RAM (cf. §3) contre 7,6 Go pour la VM Liora, sans
swap — Airflow (webserver + scheduler + DB dediee, cf. piste dlt ci-dessus) est
naturellement plus a sa place sur la machine qui a la marge. Ecrire les manifests K8s
(`base/airflow/` + overlays) pour qu'Airflow tourne sur Talos, en ingerant dans le
Postgres du cluster (`base/postgres`), plutot que sur la VM comme ajoute cette session.

**Tension identifiee avec le mecanisme de fallback (§5)** : la VM est concue pour rester
**autonome** si le Proxmox tombe ("restauration des derniers backups DB (max 6h)" avant de
demarrer son propre docker-compose). Si l'ingestion (Airflow) ne vit que sur le Proxmox et
que la VM va chercher ses donnees en direct sur le cluster, elle perd cette autonomie —
justement dans le scenario ou elle est censee prendre le relais.

**Verification faite le 2026-07-23** : le mecanisme cense reconcilier ça — un `CronJob`
K8s de backup (`pg_dump` du Postgres cluster, toutes les 6h, envoye par SCP vers la VM) +
un script `/opt/fallback.sh` sur la VM qui restaure ce dump avant de lancer
`docker compose` — est **decrit dans `docs/INSTALL.md` §7 mais n'existe nulle part dans le
repo, ni sur la VM**. Toute la checklist "Phase 7 : Backups et fallback" d'`INSTALL.md` est
encore a cases non cochees. Ce n'est donc pas "deplacer Airflow en gardant le fallback
existant" mais **construire tout le pipeline d'un coup** si cette piste est retenue :
manifests Airflow K8s + le `CronJob` de backup + le script de restauration VM, comme un
seul chantier coherent (pas trois taches independantes).

**A trancher** : est-ce qu'on garde Airflow sur la VM (deja teste, deja merge — cf.
`crypto-bot-infra/ansible/TESTS.md`) en acceptant la contrainte RAM, ou est-ce qu'on
construit ce pipeline complet vers le Proxmox et on retire Airflow de la VM ? Les deux
options sont valables, aucune n'est implementee au-dela de "Airflow sur la VM" a ce jour.

**Statut** : les trois pistes ci-dessus (k3s, dlt, Airflow-sur-Proxmox) sont des decisions
ouvertes, soulevees mais non tranchees le 2026-07-23. Ne pas les implementer sans
validation explicite prealable.
