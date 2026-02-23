# Architecture Crypto-Bot

## 1. Contexte et objectifs

### Situation actuelle

- Backend FastAPI (:8009) + Frontend Streamlit (:8501)
- BDD : PostgreSQL 14, MongoDB, MinIO (S3-compatible)
- CI/CD : GitLab CI (lint > test > build > deploy via SSH)
- Infra : Docker Compose sur VM AWS DataScientest
  - staging (:8009/:8501) et production (:9009/:8502) sur la meme VM
- Registry : GitLab Container Registry (`registry.gitlab.com/dst_crypto/crypto-bot`)

### Materiel disponible

| Ressource | Specs | Role |
|-----------|-------|------|
| **Serveur Proxmox (P1)** | 64 GB RAM, 512 GB SSD | Cluster K8s complet |
| VM AWS DataScientest | 2 vCPU, 7.6 GB RAM, 29 GB | Reverse proxy + fallback |
| Dell Precision 3580 | i7 13e gen, 32 GB RAM | Dev local |

### Contraintes

| Contrainte | Impact |
|------------|--------|
| Proxmox derriere NAT entreprise | Pas d'IP publique → tunnel outbound-only |
| Proxmox = serveur d'entreprise | Securisation obligatoire, justifiable au RSI |
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
Reseau entreprise (LAN)
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

- VMs K8s sur un bridge dedie (`vmbr1`), **isole du LAN entreprise**
- **Zero port entrant** sur le firewall corporate
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

![Vue globale](../diagrams/01-vue-globale.svg)

### Architecture applicative

![Architecture applicative](../diagrams/02-architecture-app.svg)

### Infrastructure Kubernetes

![Infrastructure K8s](../diagrams/03-infra-k8s.svg)

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
| Overlay network | **Flannel** (defaut Talos) | Simple, integre a Talos |
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
| Backups | **CronJob K8s** | pg_dump + mongodump toutes les 6h vers VM AWS |
