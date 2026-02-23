# Plan Kubernetes Talos OS - Crypto-Bot
# ======================================
# Projet DataScientest - Data Engineer
# Date : Fevrier 2026


## 1. Contexte et objectifs

### Situation actuelle

- Backend FastAPI (:8009) + Frontend Streamlit (:8501)
- BDD : PostgreSQL 14, MongoDB, MinIO (S3-compatible)
- CI/CD : GitLab CI (lint > test > build > deploy via SSH)
- Infra : Docker Compose sur VM AWS DataScientest
  - staging (:8009/:8501) et production (:9009/:8502) sur la meme VM
- Registry : GitLab Container Registry (`registry.gitlab.com/dst_crypto/crypto-bot`)

### Materiel disponible

| Ressource | Specs | Acces | Role |
|-----------|-------|-------|------|
| **Serveur Proxmox (P1)** | **64 GB RAM**, 512 GB SSD | Bureau alternance, configure avec RSI | Cluster K8s complet |
| VM AWS DataScientest | 2 vCPU, 7.6 GB RAM, 29 GB disque, Ubuntu | user `ubuntu`, sudo NOPASSWD, Docker 28.0.4 | Reverse proxy + fallback |
| Dell Precision 3580 (bureau) | i7 13eme gen, 32 GB DDR4, SSD | Laptop alternance | Dev local (talos-in-docker) |

### Contraintes

| Contrainte | Impact |
|------------|--------|
| Proxmox derriere NAT entreprise | Pas d'IP publique → tunnel outbound-only (Cloudflare Tunnel) |
| Proxmox = serveur d'entreprise | Securisation obligatoire, justifiable au RSI |
| VM AWS : 8.9 GB disque libre | Role minimal : reverse proxy + backups, pas de workloads lourds |
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

### Option B : VM AWS comme control plane CI/CD (proposition Perplexity)

```
VM AWS = GitLab Runner + ArgoCD (dans Docker)
PC     = 2 clusters Talos separes (staging + prod)
```

| Avantage | Inconvenient |
|----------|-------------|
| VM AWS valorisee | Necessite sudo/root (PAS DISPO) |
| 2 clusters = impressionnant | ArgoCD sur VM doit joindre le PC derriere NAT |
| | 5 VMs minimum = 12-16 GB RAM |
| | `argocd app sync` = push model, PAS du vrai GitOps |

**Problemes concrets de l'option B :**

```bash
# Perplexity propose ceci sur la VM AWS :
sudo apt update && sudo apt install -y docker.io    # PAS ROOT = IMPOSSIBLE
sudo gitlab-runner register                          # PAS ROOT = IMPOSSIBLE
docker run -d -p 8080:8080 --name argocd ...        # ArgoCD ≠ un seul container

# Perplexity propose ceci dans le CI :
argocd app sync crypto-bot-staging --server https://argocd.ton-pc:8080
# Probleme 1 : GitLab.com runners ne peuvent pas joindre un PC derriere un NAT
# Probleme 2 : c'est du PUSH (CI pousse), pas du GitOps (ArgoCD pull)
```

**Vrai GitOps (pull) vs faux GitOps (push) :**

```
PUSH (Perplexity) : CI execute "argocd app sync" → deploie
                    Si le CI est casse, on ne peut plus deployer.
                    Git n'est pas la source de verite.

PULL (notre choix) : CI commit un tag image dans le repo infra
                     ArgoCD surveille le repo en permanence
                     ArgoCD detecte le changement et sync tout seul
                     Git EST la source de verite
                     Meme sans CI, on peut corriger en editant le repo
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


## 3. Architecture hybride : hardware et budget

### Serveur Proxmox P1 (0 EUR — deja disponible)

Le serveur Proxmox a 64 GB de RAM : c'est **largement suffisant** pour un
cluster Talos complet avec staging + production + monitoring.

```
Budget RAM 64 GB :
  Proxmox host                          ~4 GB
  Talos CP (talos-cp1)                   8 GB
  Talos Worker 1 (talos-worker1)        20 GB
  Talos Worker 2 (talos-worker2)        20 GB
  ──────────────────────────────────────────────
  Total alloue                         ~52 GB
  Spare (expansion, snapshots)         ~12 GB

Budget disque 512 GB :
  Proxmox host                         ~50 GB
  Talos CP                              60 GB
  Talos Worker 1                       150 GB
  Talos Worker 2                       150 GB
  ──────────────────────────────────────────────
  Total alloue                        ~410 GB
  Spare                               ~102 GB

Verdict : TRES CONFORTABLE. Staging + production + monitoring + spare.
```

### VMs sur Proxmox

| VM | Role | vCPU | RAM | Disque |
|----|------|------|-----|--------|
| talos-cp1 | Control Plane + etcd | 4 | 8 GB | 60 GB |
| talos-worker1 | Worker (staging apps + DBs) | 6 | 20 GB | 150 GB |
| talos-worker2 | Worker (prod apps + DBs) | 6 | 20 GB | 150 GB |

### VM AWS DataScientest (0 EUR — fournie par l'ecole)

| Fonction | Detail |
|----------|--------|
| Reverse proxy Nginx | Route le trafic vers le cluster via tunnel |
| Backups off-site | Recoit les dumps DB toutes les 6h (CronJob K8s) |
| Fallback | docker-compose pret a demarrer si le Proxmox tombe |
| Bastion SSH | Acces admin securise |

### Dell Precision 3580 (dev local)

Le laptop sert uniquement au **developpement local** avec talos-in-docker
(WSL2 + Docker Desktop). Le vrai cluster tourne sur le Proxmox.

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

### Isolation reseau sur Proxmox

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
- Le Proxmox host reste accessible sur le LAN pour la gestion (https://IP:8006)

### Acces equipe (Cloudflare Tunnel)

```
Membres de l'equipe (navigateur)
    │ HTTPS
    ▼
Cloudflare Edge (TLS, Access policies)
    │ Tunnel chiffre (outbound-only depuis le cluster)
    ▼
Cluster K8s (Proxmox) → Ingress → staging ou production
```

- Zero installation cote equipe (juste un navigateur)
- Cloudflare Access peut ajouter une authentification (email OTP, GitLab SSO)
- Free tier Cloudflare suffit

### Acces admin (Tailscale)

```
Operateurs (kubectl, ArgoCD UI, Grafana)
    │ Tailscale VPN (100.x.x.x)
    ▼
Cluster K8s + VM AWS
```

- Mesh VPN gratuit (100 devices), traverse NAT
- Seuls les admins installent Tailscale, pas l'equipe entiere

### Controle d'acces par couche

| Couche | Mecanisme |
|--------|-----------|
| Proxmox host | SSH par cle uniquement, pas de mot de passe |
| Kubernetes API | RBAC : roles par namespace, tokens a duree limitee |
| ArgoCD | Authentification + roles (admin / lecteur) |
| Secrets | Sealed Secrets : chiffres dans Git, jamais en clair |
| Containers | Execution non-root (deja le cas dans les Dockerfiles) |
| Images | Pull uniquement depuis le GitLab Registry (prive) |
| Bases de donnees | ClusterIP uniquement (jamais exposees en NodePort) |

### Pourquoi Talos et pas Talos bare-metal

```
1 serveur physique + Talos bare-metal = 1 seul noeud Kubernetes

Mais on veut 3 noeuds (1 CP + 2 workers) sur 1 machine.
→ Proxmox cree 3 VMs, chaque VM boot sur Talos ISO.
→ Chaque VM = un noeud K8s independant.

┌──────────────────────────────┐
│  VM Talos CP    (8 GB RAM)   │  noeud K8s control plane
│  VM Talos W1    (20 GB RAM)  │  noeud K8s worker 1
│  VM Talos W2    (20 GB RAM)  │  noeud K8s worker 2
├──────────────────────────────┤
│  Proxmox VE                  │  hyperviseur (~4 GB RAM)
├──────────────────────────────┤
│  Serveur physique (64 GB)    │
└──────────────────────────────┘
```


---


## 5. Architecture cible

### Schema global

```
                    INTERNET
                       │
                       ▼
            ┌─────────────────────┐
            │   VM AWS (7.6 GB)   │  IP publique : 13.37.234.206
            │                     │
            │  Nginx reverse      │
            │  proxy              │
            │  Backups DB (6h)    │
            │  Fallback docker-   │
            │  compose (eteint)   │
            └────────┬────────────┘
                     │ Tunnel chiffre (outbound-only)
                     │ Zero port entrant cote entreprise
                     ▼
    ┌════════════════════════════════════════════════════┐
    ║           SERVEUR PROXMOX P1 (64 GB)               ║
    ║           Bridge isole vmbr1                        ║
    ║                                                     ║
    ║  ┌────────────┐  ┌─────────────┐  ┌─────────────┐ ║
    ║  │ talos-cp1  │  │ talos-w1    │  │ talos-w2    │ ║
    ║  │ 4C / 8 GB  │  │ 6C / 20 GB  │  │ 6C / 20 GB  │ ║
    ║  │ 60 GB      │  │ 150 GB      │  │ 150 GB      │ ║
    ║  │ CP + etcd  │  │ Worker 1    │  │ Worker 2    │ ║
    ║  └────────────┘  └─────────────┘  └─────────────┘ ║
    ║                                                     ║
    ║  ┌───────────────────┐  ┌───────────────────┐      ║
    ║  │  ns: staging      │  │  ns: production   │      ║
    ║  │  backend/frontend │  │  backend/frontend │      ║
    ║  │  postgres/mongo   │  │  postgres/mongo   │      ║
    ║  │  minio            │  │  minio            │      ║
    ║  └───────────────────┘  └───────────────────┘      ║
    ║                                                     ║
    ║  ArgoCD │ MetalLB │ Ingress NGINX │ Sealed Secrets ║
    ║  Loki + Promtail + Grafana │ Cloudflare Tunnel     ║
    ╚════════════════════════════════════════════════════╝

    ┌════════════════════════════════════════════════════┐
    ║              GITLAB CI/CD PIPELINE                  ║
    ║                                                     ║
    ║  git push (staging ou tag)                          ║
    ║       │                                             ║
    ║       ▼                                             ║
    ║  Lint → Test → Build & Push images (GitLab Reg.)   ║
    ║       │                                             ║
    ║       ▼                                             ║
    ║  Update tag image dans repo crypto-bot-infra        ║
    ║  (commit auto)                                      ║
    ║       │                                             ║
    ║       ▼                                             ║
    ║  ArgoCD detecte & sync sur le cluster Talos         ║
    ║  staging = auto-sync │ production = sync manuel     ║
    ╚════════════════════════════════════════════════════╝
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
| Monitoring | **Loki + Promtail + Grafana** | Logs centralises (Helm chart grafana/loki-stack v2.10.3) |
| Acces equipe | **Cloudflare Tunnel** | Outbound-only, zero port entrant, free tier |
| Acces admin | **Tailscale** | Mesh VPN gratuit, traverse NAT |
| VM AWS | **Nginx + docker-compose fallback** | Reverse proxy + resilience |
| Backups | **CronJob K8s** | pg_dump + mongodump toutes les 6h vers VM AWS |


---


## 6. Plan d'action detaille

### Phase 0 : Installer Proxmox et preparer le serveur (jour 0)

#### 0.1 Creer la cle USB bootable

Sur le laptop Windows :

1. Telecharger l'ISO Proxmox VE : https://www.proxmox.com/en/downloads
2. Telecharger Rufus : https://rufus.ie/
3. Lancer Rufus → selectionner la cle USB → selectionner l'ISO → **DD mode** (pas ISO mode) → Start

#### 0.2 Installer Proxmox

Booter le serveur sur la cle USB (F2/F12/DEL pour le BIOS, boot USB en premier).

L'installeur graphique demande :

| Ecran | Quoi mettre |
|-------|-------------|
| Disque cible | Le SSD 512 GB (ext4 suffit) |
| Pays / timezone | France / Europe/Paris |
| Mot de passe root | Un mot de passe solide (le noter) |
| Email | Email pro (pour les alertes) |
| Interface reseau | L'interface connectee au LAN |
| Hostname | `proxmox-p1.local` (ou selon le RSI) |
| IP | Une IP libre sur le LAN (demander au RSI, ex: `192.168.1.50/24`) |
| Gateway | Passerelle du LAN (ex: `192.168.1.1`) |
| DNS | DNS entreprise (demander au RSI, ou `1.1.1.1`) |

Note : le serveur a besoin d'etre sur le LAN avec acces internet pour
l'installation initiale (mise a jour + installation Tailscale).
Seule question a poser au RSI : "quelle IP libre je peux utiliser ?"
Apres l'installation de Tailscale, tout l'acces passe par Tailscale.

Cliquer Install → ~5 min → reboot.

#### 0.3 Post-installation

Acceder a l'interface web : `https://<IP>:8006` (login: `root`).

Depuis le shell Proxmox (Node → Shell) :

```bash
# Desactiver le repo entreprise (payant)
# Proxmox 9.x utilise le format DEB822 (.sources) et Debian Trixie
mv /etc/apt/sources.list.d/pve-enterprise.sources /etc/apt/sources.list.d/pve-enterprise.sources.disabled

# Activer le repo community (gratuit) — format DEB822
cat > /etc/apt/sources.list.d/pve-no-subscription.sources << 'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

# Mettre a jour
apt update && apt full-upgrade -y
```

#### 0.4 Installer Tailscale (acces distant sans VPN entreprise)

##### Qu'est-ce que Tailscale ?

Tailscale est un **VPN mesh** base sur WireGuard. Il cree un reseau prive
virtuel entre tes machines, quel que soit leur emplacement (bureau, maison,
cloud). Chaque machine recoit une IP stable en `100.x.x.x`.

```
SANS Tailscale :
  Laptop (maison) --X--> Proxmox (bureau, derriere NAT/firewall)
  Impossible : le Proxmox n'a pas d'IP publique, le firewall bloque

AVEC Tailscale :
  Laptop (maison) -----> Serveurs Tailscale (coordination uniquement)
  Proxmox (bureau) ----> Serveurs Tailscale (coordination uniquement)
       │                        │
       └── connexion directe ───┘  (peer-to-peer, chiffree WireGuard)

  Laptop        : 100.100.1.10
  Proxmox       : 100.100.1.20
  VM AWS        : 100.100.1.30
  → Ils se voient comme s'ils etaient sur le meme LAN
```

##### Comment ca marche techniquement

1. Chaque machine installe le client Tailscale
2. Le client etablit une **connexion sortante** vers les serveurs Tailscale
   (port 443 HTTPS — le meme que n'importe quel site web)
3. Les serveurs Tailscale ne font que la **coordination** (echange de cles,
   decouverte des pairs). Ils ne voient jamais le trafic.
4. Les machines etablissent ensuite une **connexion directe** entre elles
   (peer-to-peer via WireGuard, chiffrement de bout en bout)
5. Si le peer-to-peer echoue (NAT tres restrictif), le trafic passe par
   des relais Tailscale (DERP), toujours chiffre

##### Risques pour le reseau de l'entreprise

| Risque potentiel | Realite | Mitigation |
|-----------------|---------|------------|
| **Tailscale ouvre un acces au LAN** | **Non.** Par defaut, Tailscale ne donne acces qu'a la machine elle-meme (le Proxmox), PAS au reste du LAN. Il faut activer explicitement le "subnet routing" pour exposer le LAN, ce qu'on ne fait PAS. | Ne pas activer `--advertise-routes` |
| **Trafic non controle** | Le trafic Tailscale sort en HTTPS (port 443), comme n'importe quelle navigation web. Le firewall ne peut pas le distinguer. | C'est un avantage (traverse les firewalls) mais aussi un risque si la politique IT interdit les tunnels. **En parler au RSI.** |
| **Donnees qui sortent** | Seul le trafic entre tes machines passe par Tailscale. Aucune donnee de l'entreprise ne transite, car le Proxmox est isole (bridge vmbr1 pour K8s, pas de route vers le LAN). | Bridge isole + pas de subnet routing |
| **Compte Tailscale compromis** | Si ton compte Tailscale est pirate, l'attaquant peut acceder au Proxmox. | MFA sur le compte Tailscale + ACLs Tailscale pour limiter qui accede a quoi |
| **Politique IT** | Certaines entreprises interdisent les VPN personnels sur le reseau. | **Demander l'accord du RSI avant.** Argument : "c'est outbound-only sur port 443, ca n'expose rien du LAN, et c'est utilise en entreprise (Tailscale a des clients corporate)." |

**Resume pour le RSI :**

> "Tailscale me permet d'acceder a distance uniquement a mon serveur Proxmox,
> pas au reste du reseau. C'est une connexion sortante sur port 443 (comme
> du HTTPS normal), chiffree de bout en bout (WireGuard). Aucun port entrant
> n'est ouvert. Le serveur Proxmox heberge des VMs sur un bridge isole qui
> n'a aucun acces au LAN de l'entreprise."

##### Installation

```bash
# Sur le Proxmox host (necessite internet, donc apres l'install sur le LAN)
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up

# Suivre le lien affiche pour connecter le noeud a ton compte Tailscale
# Le Proxmox recoit une IP stable 100.x.x.x
```

```bash
# Sur ton laptop (Windows/WSL2/Mac)
# Installer Tailscale : https://tailscale.com/download
tailscale up
```

Une fois les deux machines sur le meme tailnet :

```bash
# Acceder a l'interface web Proxmox depuis n'importe ou
# https://100.x.x.x:8006 (remplacer par l'IP Tailscale du Proxmox)

# SSH direct
ssh root@100.x.x.x
```

Verifier que ca marche :

```bash
# Depuis ton laptop
tailscale status        # Doit montrer le Proxmox en "active"
ping 100.x.x.x         # Doit repondre
```

##### Free tier Tailscale

- 100 devices, 3 utilisateurs
- Largement suffisant pour ce projet
- Pas de carte bancaire requise

#### 0.5 Configurer le bridge isole pour K8s

Dans l'interface web Proxmox : Node → Network → Create → Linux Bridge

| Parametre | Valeur |
|-----------|--------|
| Name | `vmbr1` |
| IPv4/CIDR | `10.10.0.1/24` |
| Bridge ports | *(laisser vide = reseau interne uniquement)* |
| Comment | `K8s cluster isolated network` |

Cliquer Apply Configuration.

#### 0.5b Configurer le NAT et DHCP pour vmbr1

Le bridge vmbr1 est isole (pas de port physique). Pour que les VMs aient
internet, le Proxmox host doit faire office de routeur NAT. Il faut aussi
un serveur DHCP pour distribuer les IPs aux VMs Talos.

```bash
# --- NAT : permettre aux VMs (vmbr1) de sortir sur internet via vmbr0 ---

# Activer le routage IP (le Proxmox devient un routeur)
echo 1 > /proc/sys/net/ipv4/ip_forward
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# Regle NAT : les paquets de 10.10.0.0/24 sont masquerades via vmbr0
iptables -t nat -A POSTROUTING -s 10.10.0.0/24 -o vmbr0 -j MASQUERADE

# Autoriser le forwarding entre les deux bridges
iptables -A FORWARD -i vmbr1 -o vmbr0 -j ACCEPT
iptables -A FORWARD -i vmbr0 -o vmbr1 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Rendre les regles persistantes (survit au reboot)
apt install -y iptables-persistent
# Repondre "Yes" aux deux questions


# --- DHCP/DNS : distribuer les IPs aux VMs sur vmbr1 ---

apt install -y dnsmasq

cat > /etc/dnsmasq.d/vmbr1.conf << 'EOF'
interface=vmbr1
dhcp-range=10.10.0.100,10.10.0.200,24h
dhcp-option=option:router,10.10.0.1
dhcp-option=option:dns-server,8.8.8.8,1.1.1.1
EOF

systemctl restart dnsmasq
```

Explication :
- **NAT (MASQUERADE)** : les VMs envoient leur trafic au Proxmox (gateway 10.10.0.1),
  qui le retransmet sur vmbr0 en remplacant l'IP source. Pour le reseau entreprise,
  tout le trafic semble venir du Proxmox.
- **dnsmasq** : serveur DHCP leger qui attribue des IPs dans la plage
  10.10.0.100-200 aux VMs, avec le Proxmox comme gateway et 8.8.8.8 comme DNS.
- Les VMs Talos obtiennent une IP automatiquement au boot (DHCP).

#### 0.6 Telecharger l'ISO Talos

```bash
# Sur le Proxmox host
cd /var/lib/vz/template/iso/
wget https://github.com/siderolabs/talos/releases/download/v1.12.3/metal-amd64.iso
```

#### 0.7 Installer les outils CLI (sur le laptop)

```bash
# talosctl
curl -sL https://talos.dev/install | sh
talosctl version --client

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/
```

Avec Tailscale, tu pourras ensuite utiliser `talosctl` et `kubectl` depuis
ton laptop en pointant vers les IPs Tailscale des noeuds du cluster.

---

### Phase 1 : Creer le cluster Talos sur Proxmox (jour 1-2)

#### 1.1 Creer les VMs dans Proxmox

| VM | VMID | Role | vCPU | RAM | Disque | Reseau |
|----|------|------|------|-----|--------|--------|
| talos-cp1 | 100 | Control Plane | 2 | 4 GB | 20 GB | vmbr1 |
| talos-worker1 | 101 | Worker | 4 | 10 GB | 50 GB | vmbr1 |
| talos-worker2 | 102 | Worker | 4 | 10 GB | 50 GB | vmbr1 |

Note : specs initiales reduites par rapport au budget cible (section 3).
Augmentables a chaud via Proxmox si besoin (RAM cible : CP 8 GB, Workers 20 GB).

Pour chaque VM :
- OS : Other (Talos n'est pas dans la liste)
- Boot : CD-ROM (ISO Talos)
- Disque : VirtIO, format qcow2
- Reseau : vmbr1, modele VirtIO

Demarrer les 3 VMs. Talos affiche son IP sur la console. Les noter.

#### 1.2 Generer et appliquer la configuration

```bash
# Generer les fichiers de config
talosctl gen config crypto-bot https://<IP_CP>:6443 \
  --output-dir _talos_config

# Appliquer au control plane
talosctl apply-config --insecure \
  --nodes <IP_CP> \
  --file _talos_config/controlplane.yaml

# Appliquer aux workers
talosctl apply-config --insecure \
  --nodes <IP_WORKER_1> \
  --file _talos_config/worker.yaml

talosctl apply-config --insecure \
  --nodes <IP_WORKER_2> \
  --file _talos_config/worker.yaml
```

#### 1.3 Bootstrap

```bash
export TALOSCONFIG="_talos_config/talosconfig"
talosctl config endpoint <IP_CP>
talosctl config node <IP_CP>

talosctl bootstrap

talosctl kubeconfig ./kubeconfig
export KUBECONFIG=./kubeconfig

kubectl get nodes
# Attendu : 3 noeuds Ready (2-3 minutes)
```

#### Dev local (optionnel) : talos-in-docker sur le laptop

Pour tester en local avant de deployer sur Proxmox :

```bash
# WSL2 + Docker Desktop
# IMPORTANT : utiliser "docker" (pas "dev" qui necessite QEMU)
talosctl cluster create docker --name crypto-bot \
  --workers 2 \
  --memory-controlplanes 2048MB \
  --memory-workers 2048MB \
  --cpus-controlplanes 2 \
  --cpus-workers 2
```

---

### Phase 2 : Infra de base sur le cluster (jour 2-3)

#### 2.1 MetalLB

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml

kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=90s
```

Creer `metallb-config.yaml` :

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
    - 10.10.0.240-10.10.0.250   # Plage sur le bridge isole vmbr1
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
```

```bash
kubectl apply -f metallb-config.yaml
```

Note : avec talos-in-docker (dev local), MetalLB n'est pas necessaire.
Utiliser `kubectl port-forward` pour acceder aux services.

#### 2.2 Ingress NGINX Controller

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.0/deploy/static/provider/cloud/deploy.yaml

kubectl get svc -n ingress-nginx ingress-nginx-controller
# EXTERNAL-IP doit afficher une IP de la plage MetalLB
```

#### 2.3 Storage : local-path-provisioner

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml

kubectl patch storageclass local-path \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Talos applique PodSecurity "baseline" par defaut.
# Le provisioner cree des helper pods avec hostPath → bloque par baseline.
# Il faut passer le namespace en mode "privileged" :
kubectl label ns local-path-storage pod-security.kubernetes.io/enforce=privileged
```

> **Important** : cette commande `kubectl label` est necessaire apres chaque reinstallation du cluster.
> Sans elle, les PVCs resteront en `Pending` (les helper pods de local-path-provisioner seront rejetes).

#### 2.4 Creer les namespaces

```bash
kubectl create namespace staging
kubectl create namespace production
```

#### 2.5 Sealed Secrets

```bash
# Installer le controller Sealed Secrets dans kube-system
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.29.0/controller.yaml

# Verifier que le controller est Running
kubectl get pods -n kube-system -l name=sealed-secrets-controller

# Installer kubeseal CLI sur le poste local
# Linux :
KUBESEAL_VERSION=0.29.0
curl -OL "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"
tar -xvzf kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal

# Tester
kubeseal --version
```

Usage pour chiffrer un secret :

```bash
# Creer un secret classique (ne pas l'appliquer !)
kubectl create secret generic crypto-bot-secrets \
  --from-literal=POSTGRES_USER=postgres \
  --from-literal=POSTGRES_PWD=changeme \
  --dry-run=client -o yaml > secret.yaml

# Chiffrer avec kubeseal
kubeseal --format=yaml < secret.yaml > sealed-secret.yaml

# Le fichier sealed-secret.yaml peut etre commite dans Git en toute securite.
# Seul le controller dans le cluster peut le dechiffrer.
```

#### 2.6 Monitoring : Loki + Promtail + Grafana

```bash
# Ajouter le repo Helm Grafana
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Creer le namespace monitoring (avec PodSecurity privileged pour Promtail)
kubectl create namespace monitoring
kubectl label ns monitoring pod-security.kubernetes.io/enforce=privileged

# Installer la stack Loki (Loki + Promtail + Grafana)
helm install loki grafana/loki-stack \
  --namespace monitoring \
  --set grafana.enabled=true \
  --set loki.persistence.enabled=true \
  --set loki.persistence.size=5Gi \
  --version 2.10.3

# Verifier les pods (5 attendus : loki-0, grafana, 3x promtail)
kubectl get pods -n monitoring

# Recuperer le mot de passe Grafana (SealedSecret grafana-admin)
kubectl get secret grafana-admin -n monitoring -o jsonpath="{.data.admin-password}" | base64 -d

# Acceder a Grafana (port-forward)
kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80
# → http://localhost:3000, login : admin / <mot de passe ci-dessus>
```

> **Important** : le label `pod-security.kubernetes.io/enforce=privileged` sur le
> namespace `monitoring` est **requis** pour que les pods Promtail puissent monter
> les hostPath des logs. Sans ce label, les DaemonSets Promtail seront rejetes.

Loki est pre-configure comme datasource dans Grafana. Pour voir les logs :
1. Aller dans Explore
2. Selectionner la datasource "Loki"
3. Utiliser une requete LogQL, ex : `{namespace="staging"}`

> **Migration GitOps (Phase 8b)** : l'installation Helm manuelle ci-dessus est remplacee par
> une ArgoCD Application multi-source (`argocd/monitoring-app.yaml`). ArgoCD deploie le meme
> chart Helm loki-stack + un dashboard Grafana provisionne automatiquement via ConfigMap.
> Transition : `helm uninstall loki -n monitoring` puis ArgoCD recree tout.
> Voir `monitoring/` dans le repo pour les extras (dashboards).

---

### Phase 3 : Repo GitOps crypto-bot-infra (jour 3-5)

#### 3.1 Creer le repo sur GitLab

Creer `crypto-bot-infra` sur GitLab (groupe `dst_crypto`).

#### 3.2 Structure du repo

```
crypto-bot-infra/
│
├── base/                           # Ressources Kustomize communes
│   ├── kustomization.yaml
│   ├── backend/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── kustomization.yaml
│   ├── frontend/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── kustomization.yaml
│   ├── postgres/
│   │   ├── statefulset.yaml
│   │   ├── service.yaml
│   │   └── kustomization.yaml
│   ├── mongo/
│   │   ├── statefulset.yaml
│   │   ├── service.yaml
│   │   └── kustomization.yaml
│   └── minio/
│       ├── statefulset.yaml
│       ├── service.yaml
│       └── kustomization.yaml
│
├── overlays/
│   ├── staging/
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml
│   │   ├── ingress.yaml
│   │   └── secrets.yaml
│   └── production/
│       ├── kustomization.yaml
│       ├── namespace.yaml
│       ├── ingress.yaml
│       └── secrets.yaml
│
├── monitoring/                        # Extras monitoring (dashboards Grafana)
│   ├── kustomization.yaml
│   └── grafana-dashboard-crypto-bot.yaml
│
└── argocd/
    ├── staging-app.yaml             # ArgoCD Application (auto-sync)
    ├── production-app.yaml          # ArgoCD Application (sync manuel)
    └── monitoring-app.yaml          # ArgoCD Application monitoring (Helm + extras)
```

#### 3.3 Exemples de manifests cles

**base/backend/deployment.yaml** :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: crypto-bot-backend
  labels:
    app: crypto-bot-backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: crypto-bot-backend
  template:
    metadata:
      labels:
        app: crypto-bot-backend
    spec:
      imagePullSecrets:
        - name: gitlab-registry
      containers:
        - name: backend
          image: registry.gitlab.com/dst_crypto/crypto-bot/backend:latest
          ports:
            - containerPort: 8009
          env:
            - name: MONGODB_HOST
              value: mongo
            - name: MONGODB_PORT
              value: "27017"
            - name: POSTGRES_HOST
              value: postgres
            - name: POSTGRES_PORT
              value: "5432"
            - name: POSTGRES_DB
              value: crypto_bot_db
            - name: MINIO_ENDPOINT
              value: minio:9000
            - name: MINIO_SECURE
              value: "0"
            - name: MINIO_BUCKET
              value: crypto-bot-data
          envFrom:
            - secretRef:
                name: crypto-bot-secrets
          livenessProbe:
            httpGet:
              path: /health
              port: 8009
            initialDelaySeconds: 40
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /health
              port: 8009
            initialDelaySeconds: 20
            periodSeconds: 10
          resources:
            requests:
              memory: "256Mi"
              cpu: "200m"
            limits:
              memory: "512Mi"
              cpu: "500m"
```

**base/backend/service.yaml** :

```yaml
apiVersion: v1
kind: Service
metadata:
  name: crypto-bot-backend
spec:
  selector:
    app: crypto-bot-backend
  ports:
    - port: 8009
      targetPort: 8009
```

**base/postgres/statefulset.yaml** :

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:14
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_DB
              value: crypto_bot_db
          envFrom:
            - secretRef:
                name: crypto-bot-secrets
          volumeMounts:
            - name: postgres-data
              mountPath: /var/lib/postgresql/data
          readinessProbe:
            exec:
              command: ["pg_isready", "-U", "postgres"]
            initialDelaySeconds: 30
            periodSeconds: 10
          resources:
            requests:
              memory: "256Mi"
              cpu: "200m"
            limits:
              memory: "512Mi"
              cpu: "500m"
  volumeClaimTemplates:
    - metadata:
        name: postgres-data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 5Gi
```

**overlays/staging/kustomization.yaml** :

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: staging

resources:
  - ../../base
  - ingress.yaml
  - secrets.yaml

patches:
  - target:
      kind: Deployment
      name: crypto-bot-backend
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/image
        value: registry.gitlab.com/dst_crypto/crypto-bot/backend:staging
      - op: add
        path: /spec/template/spec/containers/0/env/-
        value:
          name: ENVIRONMENT
          value: staging
      - op: add
        path: /spec/template/spec/containers/0/env/-
        value:
          name: DEBUG
          value: "true"

  - target:
      kind: Deployment
      name: crypto-bot-frontend
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/image
        value: registry.gitlab.com/dst_crypto/crypto-bot/frontend:staging
```

**overlays/staging/ingress.yaml** :

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: crypto-bot-ingress
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
spec:
  ingressClassName: nginx
  rules:
    - host: staging.crypto-bot.local
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: crypto-bot-backend
                port:
                  number: 8009
          - path: /
            pathType: Prefix
            backend:
              service:
                name: crypto-bot-frontend
                port:
                  number: 8501
```

**argocd/staging-app.yaml** :

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: crypto-bot-staging
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://gitlab.com/dst_crypto/crypto-bot-infra.git
    targetRevision: main
    path: overlays/staging
  destination:
    server: https://kubernetes.default.svc
    namespace: staging
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**argocd/production-app.yaml** :

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: crypto-bot-production
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://gitlab.com/dst_crypto/crypto-bot-infra.git
    targetRevision: main
    path: overlays/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    # PAS de automated : sync manuel pour la prod
    syncOptions:
      - CreateNamespace=true
```

---

### Phase 4 : Installer ArgoCD (jour 5-6)

#### 4.1 Installation

```bash
kubectl create namespace argocd

kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl wait --namespace argocd \
  --for=condition=available deployment \
  --all --timeout=300s
```

#### 4.2 Acceder a l'UI ArgoCD

```bash
# Mot de passe initial
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Exposer l'UI
kubectl port-forward svc/argocd-server -n argocd 8443:443

# https://localhost:8443 — Login : admin / <mot de passe>
```

#### 4.3 Configurer le repo GitLab

```bash
argocd login localhost:8443 --insecure

argocd repo add https://gitlab.com/dst_crypto/crypto-bot-infra.git \
  --username gitlab-ci-token \
  --password <DEPLOY_TOKEN>
```

#### 4.4 Creer un GitLab Deploy Token

GitLab > `crypto-bot-infra` > Settings > Repository > Deploy tokens :
- Name : `argocd-read`
- Scopes : `read_repository`

#### 4.5 Deployer les Applications

```bash
kubectl apply -f argocd/staging-app.yaml
kubectl apply -f argocd/production-app.yaml
```

#### 4.6 ImagePullSecret

Le secret `gitlab-registry` est necessaire dans chaque namespace pour que les pods
puissent pull les images depuis le registry GitLab prive.

```bash
for NS in dev staging production; do
  kubectl create secret docker-registry gitlab-registry \
    --namespace $NS \
    --docker-server=registry.gitlab.com \
    --docker-username=<USERNAME_GITLAB> \
    --docker-password=<PERSONAL_ACCESS_TOKEN>
done
```

> **Notes** :
> - Le username est celui de votre compte GitLab (visible sur votre profil `@username`)
> - Le password est un **Personal Access Token** (PAT, commence par `glpat-`) avec le scope `read_registry`
> - Ne pas confondre avec un deploy token (`gldt-`) — utiliser un PAT personnel

---

### Phase 5 : Adapter le pipeline GitLab CI (jour 6-7)

#### 5.1 Remplacer le deploy SSH par update-manifests

Le pipeline GitLab CI ne deploie plus via SSH. Il met a jour le tag image
dans le repo infra, et ArgoCD fait le reste.

```yaml
stages:
  - lint
  - test
  - build
  - update-manifests    # Update tag dans crypto-bot-infra → ArgoCD sync

update:manifests:
  stage: update-manifests
  image: alpine:latest
  before_script:
    - apk add --no-cache git curl
  script:
    - |
      git clone https://gitlab-ci-token:${INFRA_DEPLOY_TOKEN}@gitlab.com/dst_crypto/crypto-bot-infra.git
      cd crypto-bot-infra

      git config user.email "ci@crypto-bot.gitlab.com"
      git config user.name "GitLab CI"

      # Determine le tag semantique selon le contexte
      if [ -n "$CI_COMMIT_TAG" ]; then
        TAG="${CI_COMMIT_TAG}"      # ex: v1.1
        OVERLAY="prod"
      else
        TAG="staging"
        OVERLAY="staging"
      fi

      cd overlays/${OVERLAY}
      sed -i "s|backend:.*|backend:${TAG}|g" kustomization.yaml
      sed -i "s|frontend:.*|frontend:${TAG}|g" kustomization.yaml

      git add .
      git commit -m "ci: update ${OVERLAY} images to ${TAG}"
      git push origin main
  rules:
    - if: $CI_COMMIT_BRANCH == "staging"
    - if: $CI_COMMIT_TAG =~ /^v\d+\.\d+/
  variables:
    INFRA_DEPLOY_TOKEN: $INFRA_DEPLOY_TOKEN
```

Note : la CI utilise des tags semantiques (`:staging`, `:vX.X`) et jamais de SHA.
ArgoCD detecte le changement dans le repo infra et synchronise le cluster.
Le deploy SSH vers la VM AWS est maintenu comme fallback (docker-compose).

#### 5.2 Sync bidirectionnel entre les repos

Les 3 repos applicatifs (crypto-bot, backend, frontend) se synchronisent
automatiquement via la CI. Voir `docs/GIT_WORKFLOW.md` pour le detail.

Resume :
- Push sur **backend** ou **frontend** → CI lance `sync:parent` → met a jour
  le pointer submodule dans crypto-bot (commit `ci(backend): ...`)
- Push sur **crypto-bot** → CI lance `sync:submodules` → push les commits
  referencies vers backend/frontend
- **Anti-boucle** : tout commit dont le message commence par `ci(` est ignore
  par les jobs de sync.
- Variable **GROUP_PAT_TOKEN** : PAT au niveau du groupe `dst_crypto`, scope
  `write_repository`, accessible par les 3 repos sans duplication.

---

### Phase 6 : Tunnel et reverse proxy (jour 7-8)

#### 6.1 Cloudflare Tunnel (acces equipe)

```bash
# Sur le cluster K8s, deployer cloudflared
kubectl create namespace cloudflare
# Configurer via Cloudflare Zero Trust dashboard :
# - Creer un tunnel
# - Associer les sous-domaines :
#   staging.crypto-bot.<domaine> → http://ingress-nginx.ingress-nginx:80
#   app.crypto-bot.<domaine>     → http://ingress-nginx.ingress-nginx:80
#   argocd.crypto-bot.<domaine>  → http://argocd-server.argocd:443
```

#### 6.2 Tailscale (acces admin)

```bash
# Sur chaque noeud K8s (ou sur le Proxmox host)
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up

# Sur la VM AWS aussi
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up

# Tester : depuis ton laptop (avec Tailscale)
kubectl --server=https://<TAILSCALE_IP_CP>:6443 get nodes
```

#### 6.3 Nginx reverse proxy sur la VM AWS

```nginx
# /etc/nginx/sites-available/crypto-bot
upstream k8s_cluster {
    server <TAILSCALE_IP_INGRESS>:80;
}

server {
    listen 80;
    server_name staging.crypto-bot.local app.crypto-bot.local;

    location / {
        proxy_pass http://k8s_cluster;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

---

### Phase 7 : Backups et fallback (jour 8-9)

#### 7.1 CronJob backup des bases (K8s → VM AWS)

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: db-backup
  namespace: production
spec:
  schedule: "0 */6 * * *"    # Toutes les 6h
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: backup
              image: alpine:latest
              command:
                - /bin/sh
                - -c
                - |
                  apk add --no-cache postgresql-client mongodb-tools openssh-client
                  # PostgreSQL
                  pg_dump -h postgres -U postgres crypto_bot_db | gzip > /tmp/pg_backup.sql.gz
                  # MongoDB
                  mongodump --host mongo --username $MONGODB_USER --password $MONGODB_PWD \
                    --authenticationDatabase admin --archive=/tmp/mongo_backup.gz --gzip
                  # Envoyer sur la VM AWS
                  scp -i /secrets/ssh-key /tmp/*.gz ubuntu@13.37.234.206:/opt/backups/
              envFrom:
                - secretRef:
                    name: crypto-bot-secrets
              volumeMounts:
                - name: ssh-key
                  mountPath: /secrets
          volumes:
            - name: ssh-key
              secret:
                secretName: backup-ssh-key
          restartPolicy: OnFailure
```

#### 7.2 Script de fallback sur la VM AWS

```bash
#!/bin/bash
# /opt/fallback.sh - A executer si le Proxmox tombe

echo "=== Activation du fallback ==="

# 1. Restaurer les derniers backups
cd /opt/crypto-bot-prod
gunzip -c /opt/backups/pg_backup.sql.gz | docker exec -i prod-postgres psql -U postgres crypto_bot_db
docker exec -i prod-mongo mongorestore --archive --gzip < /opt/backups/mongo_backup.gz

# 2. Demarrer les containers
docker compose -f docker-compose.prod.yml up -d

# 3. Basculer Nginx vers le local
cp /etc/nginx/conf.d/fallback.conf /etc/nginx/conf.d/default.conf
nginx -s reload

echo "=== Fallback actif (RPO max 6h) ==="
```

#### 7.3 Script de retour a la normale

```bash
#!/bin/bash
# /opt/restore-normal.sh - Quand le Proxmox revient

echo "=== Retour au mode normal ==="

# 1. Remettre Nginx vers le tunnel K8s
cp /etc/nginx/conf.d/tunnel.conf /etc/nginx/conf.d/default.conf
nginx -s reload

# 2. Eteindre docker-compose
docker compose -f docker-compose.prod.yml down

echo "=== Mode normal retabli ==="
```

---

### Phase 8 : DNS local (optionnel)

```bash
# Dans /etc/hosts (ou C:\Windows\System32\drivers\etc\hosts)
<IP_METALLB_INGRESS>  staging.crypto-bot.local
<IP_METALLB_INGRESS>  crypto-bot.local
<IP_METALLB_INGRESS>  argocd.crypto-bot.local
```


### Phase 9 : GitLab Runner self-hosted (optionnel)

Deployer un GitLab Runner sur le Proxmox ou dans le cluster K8s pour executer
les pipelines CI/CD en local (au lieu des shared runners GitLab.com).

**Avantages** :
- Builds Docker plus rapides (images cachees localement)
- Pas de limite de minutes CI/CD
- Push vers le registry plus rapide (meme reseau)

```bash
# Option A : Runner Docker sur le Proxmox host
# Creer une VM ou LXC legere dediee au runner
docker run -d --name gitlab-runner --restart always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v gitlab-runner-config:/etc/gitlab-runner \
  gitlab/gitlab-runner:latest

docker exec -it gitlab-runner gitlab-runner register \
  --url https://gitlab.com \
  --token <RUNNER_REGISTRATION_TOKEN> \
  --executor docker \
  --docker-image docker:latest \
  --docker-privileged

# Option B : Runner dans le cluster K8s (executor kubernetes)
helm repo add gitlab https://charts.gitlab.io
helm install gitlab-runner gitlab/gitlab-runner \
  --namespace gitlab-runner --create-namespace \
  --set gitlabUrl=https://gitlab.com \
  --set runnerRegistrationToken=<TOKEN> \
  --set runners.privileged=true
```

> Pour obtenir le token : GitLab > Groupe `dst_crypto` > Settings > CI/CD > Runners > New group runner.

---


## 7. Verification et checklists

### Checklist Phase 0-1 : Proxmox + Cluster Talos

- [x] Bridge isole `vmbr1` cree sur Proxmox
- [x] ISO Talos telecharge sur le Proxmox
- [x] talosctl et kubectl installes
- [x] 3 VMs creees (CP 8GB + 2 Workers 20GB)
- [x] Config Talos generee et appliquee
- [x] Cluster bootstrap reussi
- [x] `kubectl get nodes` = 3 noeuds Ready

### Checklist Phase 2-3 : Infra K8s + GitOps

- [x] MetalLB installe (plage 10.10.0.240-250)
- [x] Ingress NGINX installe
- [x] local-path-provisioner installe
- [x] Label `pod-security.kubernetes.io/enforce=privileged` sur ns `local-path-storage`
- [x] Sealed Secrets controller installe (ns kube-system)
- [x] kubeseal CLI installe sur le poste local
- [x] Loki + Promtail + Grafana installes (ns monitoring, Helm chart loki-stack)
- [x] Label `pod-security.kubernetes.io/enforce=privileged` sur ns `monitoring`
- [x] Monitoring gere par ArgoCD (argocd/monitoring-app.yaml, multi-source Helm + Kustomize)
- [x] Dashboard Grafana provisionne automatiquement (monitoring/grafana-dashboard-crypto-bot.yaml)
- [x] Namespaces dev + staging + production crees
- [x] Repo `crypto-bot-infra` complete (tous les YAML remplis)
- [x] Bug overlay prod corrige (`:production`, `DEBUG=false`)

### Checklist Phase 4-5 : ArgoCD + Pipeline

- [x] ArgoCD installe, UI accessible
- [x] Repo GitLab connecte a ArgoCD (deploy token)
- [x] Applications staging (auto-sync) + production (sync manuel) deployees
- [x] Pipeline GitLab CI : tags semantiques (:staging, :production, :vX.X)
- [x] Sync bidirectionnel configure (sync:parent + sync:submodules + anti-boucle)
- [x] GROUP_PAT_TOKEN configure au niveau du groupe dst_crypto
- [x] ImagePullSecrets crees dans les trois namespaces (dev, staging, production)

### Checklist Phase 6-7 : Tunnel + Fallback

- [ ] Cloudflare Tunnel operationnel (equipe accede via navigateur)
- [x] Tailscale installe (admin accede a kubectl, ArgoCD UI)
- [ ] Nginx reverse proxy configure sur la VM AWS
- [ ] CronJob backup toutes les 6h (PostgreSQL + MongoDB → VM AWS)
- [ ] Script fallback.sh teste (docker-compose demarre + Nginx bascule)
- [ ] Script restore-normal.sh teste

### Checklist Securite

- [x] VMs K8s sur bridge isole (vmbr1), pas d'acces au LAN
- [x] SSH par cle uniquement sur Proxmox
- [ ] RBAC K8s configure (roles par namespace)
- [x] Sealed Secrets installe (pas de secrets en clair dans Git)
- [ ] NetworkPolicies (staging ne peut pas joindre production)
- [x] Containers non-root (deja le cas)
- [ ] Document RSI : `docs/ARCHITECTURE.md`


---


## 8. Ressources utiles

- Talos Linux : https://www.talos.dev/latest/
- talosctl reference : https://www.talos.dev/latest/reference/cli/
- ArgoCD Getting Started : https://argo-cd.readthedocs.io/en/stable/getting_started/
- Kustomize : https://kustomize.io/
- MetalLB : https://metallb.universe.tf/
- NGINX Ingress : https://kubernetes.github.io/ingress-nginx/
- Proxmox VE : https://www.proxmox.com/en/proxmox-virtual-environment
- Cloudflare Tunnel : https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/
- Sealed Secrets : https://sealed-secrets.netlify.app/
- Tailscale : https://tailscale.com/kb/1017/install/


---


## 9. Points de soutenance

### Narrative recommandee

> "Nous avons une architecture hybride on-premise + cloud :
> - Un cluster Kubernetes Talos OS sur un serveur Proxmox heberge
>   staging et production avec un workflow GitOps ArgoCD.
> - Une VM AWS sert de point d'entree (reverse proxy) et de filet
>   de securite : en cas de panne du serveur, un fallback docker-compose
>   prend le relais avec les derniers backups (RPO 6h, RTO 2 min).
> - L'equipe accede a l'application via Cloudflare Tunnel, sans aucun
>   port ouvert cote entreprise.
> - L'infrastructure est entierement reproductible depuis Git : on peut
>   recreer le cluster en 30 minutes, ArgoCD redeploie tout.
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
11. **Presentation RSI** : document d'architecture pour justifier l'usage du serveur
