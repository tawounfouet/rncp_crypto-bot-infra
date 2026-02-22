# Architecture Hybride Kubernetes : On-Premise + Cloud
# =====================================================
# Proposition d'architecture pour projets necessitant resilience a moindre cout
# Applicable au projet Crypto-Bot et generalisable a d'autres projets internes


## 1. Resume executif

Cette architecture combine un serveur on-premise (Proxmox) avec une VM cloud
minimale (AWS) pour obtenir une resilience equivalente a un deploiement full-cloud,
a une fraction du cout.

| Indicateur | Full Cloud (AWS) | Hybride (notre approche) |
|------------|-----------------|--------------------------|
| Cout mensuel | ~270 EUR/mois | ~5-10 EUR/mois |
| Cout annuel | ~3 240 EUR/an | ~60-120 EUR/an |
| Resilience | Haute | Haute |
| Fallback | Multi-AZ AWS | Cloud fallback automatise |
| Scaling elastique | Oui | Non (scaling manuel) |
| Economie | Reference | **~97% d'economie** |

**Principe** : le cloud ne sert qu'a ce qu'il fait mieux que l'on-premise
(IP publique, disponibilite 24/7, backups off-site). Le compute lourd reste
sur le serveur physique ou il est deja amorti.


---


## 2. Schema d'architecture

```
                    INTERNET
                       │
                       ▼
            ┌─────────────────────┐
            │   VM Cloud (AWS)    │
            │   t3.micro (~4 EUR) │
            │                     │
            │  - Nginx (reverse   │
            │    proxy)           │
            │  - Cloudflare       │
            │    Tunnel endpoint  │
            │  - Backups DB       │
            │    (off-site)       │
            │  - Fallback         │
            │    docker-compose   │
            │    (eteint, pret)   │
            └────────┬────────────┘
                     │ Tunnel chiffre (outbound-only)
                     │ Zero port entrant cote entreprise
                     ▼
    ┌════════════════════════════════════════════┐
    ║        SERVEUR ON-PREMISE (Proxmox)        ║
    ║        64 GB RAM / 512 GB SSD              ║
    ║                                            ║
    ║   ┌──────────┐ ┌──────────┐ ┌──────────┐  ║
    ║   │ CP Node  │ │ Worker 1 │ │ Worker 2 │  ║
    ║   │ 8 GB RAM │ │ 20 GB    │ │ 20 GB    │  ║
    ║   │ etcd     │ │ staging  │ │ prod     │  ║
    ║   │ API      │ │ apps+DBs │ │ apps+DBs │  ║
    ║   └──────────┘ └──────────┘ └──────────┘  ║
    ║                                            ║
    ║   Services cluster :                       ║
    ║   - ArgoCD (GitOps, deploiement auto)      ║
    ║   - Ingress Controller (routage HTTP)      ║
    ║   - Prometheus + Grafana (monitoring)      ║
    ║   - Sealed Secrets (gestion des secrets)   ║
    ║                                            ║
    ║   Bridge reseau isole (vmbr1)              ║
    ║   Aucun acces au LAN entreprise            ║
    ╚════════════════════════════════════════════╝

    ┌════════════════════════════════════════════┐
    ║           GITLAB CI/CD PIPELINE            ║
    ║                                            ║
    ║   git push                                 ║
    ║      │                                     ║
    ║      ▼                                     ║
    ║   Lint → Test → Build → Push images        ║
    ║      │                                     ║
    ║      ▼                                     ║
    ║   Update tag dans repo infra (Git)         ║
    ║      │                                     ║
    ║      ▼                                     ║
    ║   ArgoCD detecte → deploie sur K8s         ║
    ║   (staging: auto / prod: manuel)           ║
    ╚════════════════════════════════════════════╝
```


---


## 3. Repartition des roles

### Serveur On-Premise (Proxmox)

| Fonction | Detail |
|----------|--------|
| Cluster Kubernetes | 3 VMs (1 control plane + 2 workers) |
| Environnements | Staging + Production (namespaces separes) |
| Bases de donnees | PostgreSQL, MongoDB, MinIO (sur les workers) |
| GitOps | ArgoCD surveille le repo Git et deploie automatiquement |
| Monitoring | Prometheus + Grafana (dashboards, alertes) |
| Secrets | Sealed Secrets (chiffres dans Git, dechiffres dans le cluster) |

### VM Cloud (AWS / OVH / Scaleway / n'importe quel provider)

| Fonction | Detail |
|----------|--------|
| Reverse proxy | Nginx route le trafic vers le cluster via tunnel |
| Point d'entree | IP publique fixe, accessible 24/7 |
| Backups off-site | Recoit les dumps DB toutes les 6h (CronJob K8s) |
| Fallback | docker-compose pret a demarrer si le cluster tombe |
| Bastion SSH | Acces admin securise vers le cluster |

**Cout cloud minimal** : une VM t3.micro (1 vCPU, 1 GB RAM) suffit
pour le reverse proxy + backups. Cout : ~4 EUR/mois sur AWS,
~3.50 EUR/mois sur OVH/Scaleway.


---


## 4. Mecanisme de fallback

### Fonctionnement normal

```
Utilisateur → VM Cloud (Nginx) → Tunnel → Cluster K8s (Proxmox)
```

### En cas de panne du serveur on-premise

```
1. Nginx detecte que le tunnel est mort (health check)
2. Bascule automatique (ou manuelle) vers docker-compose local
3. Restauration des derniers backups DB (max 6h de retard)
4. L'application est de nouveau accessible en ~2 minutes

Utilisateur → VM Cloud (Nginx) → docker-compose local
```

### Retour a la normale

```
1. Le serveur on-premise redmarre, le tunnel se retablit
2. Nginx re-bascule vers le cluster K8s
3. Le docker-compose local est eteint
4. (Optionnel) re-import des donnees creees pendant la panne
```

### Garanties

| Metrique | Valeur |
|----------|--------|
| Perte de donnees max (RPO) | 6h (configurable : reduire l'intervalle de backup) |
| Temps de bascule (RTO) | ~2 min (manuel) / ~30s (automatise avec Nginx health checks) |
| Disponibilite cible | ~99.5% (pannes serveur + temps de bascule) |


---


## 5. Securisation

### Isolation reseau

```
Reseau entreprise (LAN)
    │
    ├── Proxmox host (interface management, vmbr0)
    │
    └── Bridge isole K8s (vmbr1) ← AUCUN acces au LAN
         ├── VM talos-cp1
         ├── VM talos-worker1
         └── VM talos-worker2
              │
              └── Tunnel sortant uniquement → VM Cloud
```

- Les VMs K8s sont sur un bridge dedie, **isole du LAN entreprise**
- **Zero port entrant** sur le firewall corporate
- Le tunnel (Cloudflare Tunnel ou WireGuard) est **outbound-only**
- Le Proxmox host reste accessible sur le LAN pour la gestion

### Controle d'acces

| Couche | Mecanisme |
|--------|-----------|
| Proxmox host | SSH par cle uniquement, pas de mot de passe |
| Kubernetes API | RBAC : roles par namespace, tokens a duree limitee |
| ArgoCD | Authentification + roles (admin/lecteur) |
| Applications | Ingress avec TLS, authentification applicative |
| Secrets | Sealed Secrets : chiffres dans Git, jamais en clair |
| Containers | Execution non-root (deja le cas dans les Dockerfiles) |
| Images | Pull uniquement depuis le GitLab Registry (prive) |

### Monitoring et auditabilite

- **Prometheus** : metriques cluster, pods, noeuds
- **Grafana** : dashboards accessibles au RSI en lecture seule
- **Logs K8s** : audit log de toutes les actions API
- **Alertes** : notification si un pod crashe, un noeud tombe, ou le disque est plein


---


## 6. Comparatif des couts detaille

### Option A : Full Cloud AWS

| Service | Spec | Cout mensuel |
|---------|------|-------------|
| EKS (control plane) | Manage | 73 EUR |
| EC2 x3 (t3.medium) | 2 vCPU, 4 GB chacun | 90 EUR |
| RDS PostgreSQL | db.t3.micro | 30 EUR |
| DocumentDB (MongoDB) | db.t3.medium | 60 EUR |
| ALB (Load Balancer) | Standard | 20 EUR |
| EBS (stockage) | 100 GB gp3 | 10 EUR |
| **Total** | | **~283 EUR/mois** |
| **Annuel** | | **~3 400 EUR/an** |

### Option B : Architecture hybride (notre approche)

| Ressource | Spec | Cout mensuel |
|-----------|------|-------------|
| Serveur on-premise | Deja amorti | 0 EUR |
| Electricite serveur | ~15W idle | ~3 EUR |
| VM Cloud (t3.micro) | 1 vCPU, 1 GB | 4 EUR |
| Cloudflare Tunnel | Free tier | 0 EUR |
| Tailscale | Free tier (100 devices) | 0 EUR |
| **Total** | | **~7 EUR/mois** |
| **Annuel** | | **~84 EUR/an** |

### Economie

| | Full Cloud | Hybride | Economie |
|--|-----------|---------|----------|
| Mensuel | 283 EUR | 7 EUR | **276 EUR/mois** |
| Annuel | 3 400 EUR | 84 EUR | **3 316 EUR/an** |
| Sur 3 ans | 10 200 EUR | 252 EUR | **9 948 EUR** |
| Ratio | 100% | 2.5% | **97.5% d'economie** |


---


## 7. Cas d'usage adaptes

### Cette architecture est ideale pour

- Applications internes (ERP, CRM, dashboards, outils metier)
- APIs a trafic previsible et stable
- Environnements de dev / staging / pre-production
- Data pipelines et traitements batch
- Projets R&D et prototypage
- PME/ETI qui veulent du Kubernetes sans le cout cloud

### Cette architecture n'est PAS adaptee pour

- Applications avec pics de trafic imprevisibles (besoin d'autoscaling)
- Services multi-region / basse latence mondiale
- Hebergement soumis a certification (HDS, SecNumCloud, SOC2)
- Applications critiques exigeant un SLA > 99.9%
- Equipes sans competences Kubernetes (la maintenance est interne)


---


## 8. Competences : analyse detaillee

### 8.1 Competences requises et niveau

| Competence | Niveau requis | Qui la possede ? | Temps de formation |
|------------|--------------|-------------------|-------------------|
| **Administration Linux** (systemd, networking, firewall) | Intermediaire | Sysadmin, DevOps | 1-2 semaines si bases OK |
| **Proxmox / KVM** (creation VMs, snapshots, bridges) | Debutant+ | Sysadmin | 2-3 jours |
| **Kubernetes** (deploiements, services, RBAC, debug) | Intermediaire | DevOps, SRE | 2-4 semaines |
| **GitOps / ArgoCD** (Applications, sync policies) | Debutant+ | DevOps | 3-5 jours |
| **CI/CD** (GitLab CI, pipelines) | Intermediaire | DevOps, developpeurs | 1 semaine |
| **Monitoring** (Prometheus, Grafana) | Debutant+ | Sysadmin, DevOps | 2-3 jours |
| **Reseau** (tunnels, reverse proxy, Nginx) | Intermediaire | Sysadmin, RSI | 1 semaine |

### 8.2 Atouts d'internaliser ces competences

| Atout | Detail |
|-------|--------|
| **Reactivite** | Incident = resolution immediate, pas d'attente d'un prestataire |
| **Maitrise totale** | L'equipe comprend l'infra, peut l'adapter a de nouveaux projets |
| **Montee en competences** | K8s, GitOps, IaC = competences tres demandees sur le marche |
| **Cout a long terme** | Une fois forme, le collaborateur gere N projets sur la meme infra |
| **Capitalisation** | L'infra est documentee dans Git, la connaissance ne part pas avec le prestataire |
| **Agilite** | Besoin d'un nouvel env ? Un namespace en 5 min, pas un devis en 2 semaines |

### 8.3 Inconvenients / risques de l'internalisation

| Risque | Impact | Mitigation |
|--------|--------|------------|
| **Personne-cle** (bus factor) | Si le DevOps part, qui maintient ? | Documentation GitOps + former 2 personnes minimum |
| **Temps de formation** | 4-6 semaines pour un profil junior | Investissement initial, rentabilise en 3-6 mois |
| **Complexite K8s** | Courbe d'apprentissage raide | Talos simplifie (pas de SSH, API-driven, upgrades automatises) |
| **Incidents complexes** | Probleme etcd, networking, storage | Runbooks documentes + possibilite d'escalade vers un externe |
| **Veille techno** | K8s evolue vite (3 releases/an) | Talos gere les upgrades K8s via son API, reduit la charge |

### 8.4 Cout des competences

#### Option A : Recruter un DevOps/SRE

| Poste | Salaire annuel brut (France) | Charge employeur (~45%) | Cout total |
|-------|------------------------------|------------------------|------------|
| DevOps junior (0-2 ans) | 38-45k EUR | 17-20k EUR | **55-65k EUR/an** |
| DevOps confirme (3-5 ans) | 48-58k EUR | 22-26k EUR | **70-84k EUR/an** |
| SRE senior (5+ ans) | 58-75k EUR | 26-34k EUR | **84-109k EUR/an** |

Note : un DevOps ne travaille pas que sur cette infra. Il gere aussi
le CI/CD, le monitoring, la securite, et peut accompagner N projets.

#### Option B : Former un collaborateur existant

| Formation | Cout | Duree |
|-----------|------|-------|
| Formation Kubernetes (organisme agree) | 2 000 - 3 500 EUR | 3-5 jours |
| Certification CKA (Certified Kubernetes Administrator) | ~395 EUR (examen) | Preparation : 2-4 semaines |
| Formation ArgoCD / GitOps (en ligne) | 0 - 500 EUR | 1-2 semaines |
| Formation Proxmox (en ligne / labo) | 0 - 200 EUR | 2-3 jours |
| Autoformation (docs, labs, videos) | 0 EUR | 4-6 semaines |
| **Total formation** | **400 - 4 200 EUR** | **4-8 semaines** |

**Comparaison avec le full cloud :**

```
Economie infra annuelle hybride vs full cloud : ~3 316 EUR/an
Cout formation K8s d'un collaborateur        : ~2 000 - 4 200 EUR (une fois)

→ La formation est rentabilisee en moins d'un an par les economies d'infra.
→ A partir de l'annee 2, c'est du benefice net (~3 300 EUR/an d'economie).
```

#### Option C : Mix interne + ponctuel externe

| Prestation | Cout | Quand |
|------------|------|-------|
| Setup initial par un consultant DevOps | 3 000 - 8 000 EUR (forfait) | Une fois, au demarrage |
| Transfert de competences (2-3 jours) | Inclus dans le forfait | Apres le setup |
| Support ponctuel (incidents critiques) | 800 - 1 500 EUR/jour | Exceptionnel |

C'est souvent **le meilleur compromis** : un externe met en place, documente,
forme l'equipe, puis l'interne prend le relais pour la maintenance courante.

### 8.5 Externalisation : options et analyse

#### Option 1 : Infomanagement complet (MSP - Managed Service Provider)

Un prestataire gere toute l'infra K8s au quotidien.

| Avantage | Inconvenient |
|----------|-------------|
| Zero competence K8s requise en interne | Cout eleve : 1 500 - 4 000 EUR/mois |
| SLA contractuel (ex: 99.9%) | Dependance totale au prestataire |
| Astreinte 24/7 incluse | Perte de maitrise et d'agilite |
| | Delai pour tout changement (ticket → devis → planification) |
| | **Annule l'economie du hybride** (~7 EUR infra + ~3 000 EUR MSP/mois) |

**Verdict** : contre-productif pour cette architecture. Le MSP coute plus cher
que le full cloud qu'on cherche a eviter.

#### Option 2 : Support ponctuel / carnet d'heures

Un consultant DevOps est disponible sur appel pour les incidents.

| Avantage | Inconvenient |
|----------|-------------|
| Cout maitrise (~500-1500 EUR/mois pour ~10h) | Pas de proactivite (reagit, n'anticipe pas) |
| Expertise pointue disponible | Temps de reaction variable (pas de SLA strict) |
| L'interne gere le quotidien | Necessite quand meme un niveau de base en interne |

**Verdict** : bon filet de securite en complement d'une equipe interne formee.

#### Option 3 : Setup externe + maintenance interne (RECOMMANDE)

```
PHASE 1 (mois 1)      : Consultant externe installe l'infra
                         Forfait ~5 000 EUR, transfert de competences inclus

PHASE 2 (mois 2-3)    : Interne maintient avec support du consultant
                         Carnet de 10h/mois (~1 000 EUR/mois)

PHASE 3 (mois 4+)     : Interne autonome
                         Support externe sur appel uniquement
                         ~500 EUR/mois (ou 0 si pas d'incident)
```

**Cout total premiere annee :**

| Poste | Cout |
|-------|------|
| Setup consultant (forfait) | 5 000 EUR |
| Support mois 2-3 (2 x 1 000) | 2 000 EUR |
| Support mois 4-12 (9 x 500) | 4 500 EUR |
| Formation CKA collaborateur | 2 000 EUR |
| Infra (12 x 7 EUR) | 84 EUR |
| **Total annee 1** | **~13 584 EUR** |

**Cout full cloud equivalent annee 1 :**

| Poste | Cout |
|-------|------|
| AWS (12 x 283 EUR) | 3 396 EUR |
| DevOps pour gerer AWS (meme besoin) | 70 000 EUR |
| **Total annee 1** | **~73 396 EUR** |

Note : meme en full cloud, il faut quelqu'un pour gerer l'infra.
Le cloud ne supprime pas le besoin de competences, il le deplace
(de "gerer des serveurs" a "gerer des services cloud").

### 8.6 Synthese : quelle strategie choisir ?

```
┌─────────────────────┬──────────────┬──────────────────┬───────────────────┐
│                      │ Tout interne │ Setup externe +  │ MSP complet       │
│                      │              │ maint. interne   │                   │
├─────────────────────┼──────────────┼──────────────────┼───────────────────┤
│ Cout annee 1         │ ~7 500 EUR   │ ~13 600 EUR      │ ~40 000 EUR       │
│ (infra + competences)│ (si deja     │                  │                   │
│                      │ forme)       │                  │                   │
├─────────────────────┼──────────────┼──────────────────┼───────────────────┤
│ Cout annee 2+        │ ~2 000 EUR   │ ~6 000 EUR       │ ~36 000 EUR       │
├─────────────────────┼──────────────┼──────────────────┼───────────────────┤
│ Risque technique     │ Moyen        │ Faible           │ Tres faible       │
├─────────────────────┼──────────────┼──────────────────┼───────────────────┤
│ Autonomie            │ Totale       │ Haute            │ Faible            │
├─────────────────────┼──────────────┼──────────────────┼───────────────────┤
│ Montee en competences│ Forte        │ Forte            │ Aucune            │
├─────────────────────┼──────────────┼──────────────────┼───────────────────┤
│ Ideal pour           │ Equipe deja  │ PME/ETI sans     │ Entreprise sans   │
│                      │ DevOps       │ DevOps mais avec │ aucune competence │
│                      │              │ volonte de monter│ IT et sans envie  │
│                      │              │ en competences   │ d'en avoir        │
└─────────────────────┴──────────────┴──────────────────┴───────────────────┘

RECOMMANDATION : "Setup externe + maintenance interne"
→ Meilleur rapport risque/cout/autonomie pour une PME/ETI
→ La formation est un investissement, pas un cout
→ Les competences K8s/DevOps acquises servent a tous les projets futurs
```


---


## 9. Prerequis et mise en oeuvre

### Materiel minimum

| Composant | Minimum | Recommande |
|-----------|---------|------------|
| Serveur on-premise | 32 GB RAM, 256 GB SSD | 64 GB RAM, 512 GB SSD |
| VM Cloud | 1 vCPU, 1 GB RAM | 2 vCPU, 2 GB RAM |
| Connexion internet | ADSL stable | Fibre (upload > 10 Mbps) |

### Temps de mise en oeuvre

| Phase | Duree estimee |
|-------|---------------|
| Installation Proxmox + VMs | 1 jour |
| Cluster Kubernetes | 1 jour |
| ArgoCD + GitOps pipeline | 2 jours |
| Securisation + monitoring | 1 jour |
| Tests + documentation | 1 jour |
| **Total** | **~6 jours** |

### Reproductibilite

Toute l'infrastructure est definie dans Git (GitOps). En cas de perte
du serveur, le cluster complet peut etre recree en **~30 minutes** :

1. Reinstaller Proxmox + creer les VMs (15 min)
2. Bootstrapper le cluster K8s (5 min)
3. Installer ArgoCD, pointer vers le repo Git (5 min)
4. ArgoCD sync automatiquement tous les services (5 min)
5. Restaurer les backups DB depuis la VM cloud (5 min)
