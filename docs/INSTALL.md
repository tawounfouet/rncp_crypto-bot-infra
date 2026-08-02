# Installation — Reconstruction du cluster depuis zero

> A utiliser uniquement pour une **reconstruction complete** de l'infrastructure
> (nouveau serveur, disaster recovery total, ou pour comprendre comment tout a
> ete construit).
>
> - Pour le contexte, les choix d'architecture et leur justification, voir
>   [ARCHITECTURE.md](ARCHITECTURE.md).
> - Pour l'usage quotidien d'un cluster deja fonctionnel (acces, secrets,
>   workflow dev), voir [ONBOARDING.md](ONBOARDING.md).

---

## Phase 0 : Installer Proxmox et preparer le serveur (jour 0)

### 0.1 Creer la cle USB bootable

Sur le laptop Windows :

1. Telecharger l'ISO Proxmox VE : https://www.proxmox.com/en/downloads
2. Telecharger Rufus : https://rufus.ie/
3. Lancer Rufus → selectionner la cle USB → selectionner l'ISO → **DD mode** (pas ISO mode) → Start

### 0.2 Installer Proxmox

Booter le serveur sur la cle USB (F2/F12/DEL pour le BIOS, boot USB en premier).

L'installeur graphique demande :

| Ecran | Quoi mettre |
|-------|-------------|
| Disque cible | Le SSD 512 GB (ext4 suffit) |
| Pays / timezone | France / Europe/Paris |
| Mot de passe root | Un mot de passe solide (le noter) |
| Email | Email pour les alertes |
| Interface reseau | L'interface connectee au LAN (box internet) |
| Hostname | `proxmox-p1.local` (ou autre nom au choix) |
| IP | Une IP libre sur le LAN, en dehors de la plage DHCP de la box (ex: `192.168.1.50/24`), ou reservation DHCP par MAC (voir §0.2b) |
| Gateway | Passerelle du LAN (IP de la box, ex: `192.168.1.1`) |
| DNS | `1.1.1.1` ou `8.8.8.8` |

Note : le serveur a besoin d'etre sur le LAN avec acces internet pour
l'installation initiale (mise a jour + installation Tailscale).
Apres l'installation de Tailscale, l'acces a distance passe par Tailscale.

### 0.2b Reserver l'IP en DHCP sur la box (recommande)

Pour eviter que l'IP du Proxmox change au fil du temps (voir historique dans
[ONBOARDING.md](ONBOARDING.md) — coupures de courant, redemarrage sur une IP
differente), reserver l'IP par adresse MAC dans l'interface d'administration
de la box internet plutot que de mettre une IP fixe manuelle sur le Proxmox
(evite les conflits si la box distribue par ailleurs cette IP en DHCP).

Cliquer Install → ~5 min → reboot.

### 0.3 Post-installation

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

### 0.4 Installer Tailscale (acces distant simplifie)

Tailscale est un **VPN mesh** base sur WireGuard : reseau prive virtuel entre
les machines, quel que soit leur emplacement, chacune recevant une IP stable
en `100.x.x.x`.

```
SANS Tailscale :
  Laptop (deplacement) --X--> Proxmox (maison, derriere NAT/firewall)
  Impossible : le Proxmox n'a pas d'IP publique, la box bloque

AVEC Tailscale :
  Laptop (deplacement) --> Serveurs Tailscale (coordination uniquement)
  Proxmox (maison)     --> Serveurs Tailscale (coordination uniquement)
       │                        │
       └── connexion directe ───┘  (peer-to-peer, chiffree WireGuard)
```

#### Securite du modele Tailscale

| Risque potentiel | Realite | Mitigation |
|-----------------|---------|------------|
| **Tailscale ouvre un acces au LAN** | **Non.** Par defaut, Tailscale ne donne acces qu'a la machine elle-meme (le Proxmox), PAS au reste du LAN. Il faut activer explicitement le "subnet routing" pour exposer le LAN, ce qu'on ne fait PAS. | Ne pas activer `--advertise-routes` vers le LAN domestique |
| **Trafic non controle** | Le trafic Tailscale sort en HTTPS (port 443), comme n'importe quelle navigation web. | Comportement attendu, rien a filtrer cote box |
| **Donnees qui sortent** | Seul le trafic entre les machines du tailnet passe par Tailscale. Le Proxmox est isole (bridge vmbr1 pour K8s, pas de route vers le LAN). | Bridge isole + pas de subnet routing vers le LAN |
| **Compte Tailscale compromis** | Si le compte est pirate, l'attaquant peut acceder au Proxmox. | MFA sur le compte Tailscale + ACLs pour limiter qui accede a quoi |

> Tailscale permet d'acceder a distance uniquement au serveur Proxmox, pas
> au reste du reseau domestique. C'est une connexion sortante sur port 443
> (comme du HTTPS normal), chiffree de bout en bout (WireGuard). Aucun port
> entrant n'est ouvert sur la box. Le serveur Proxmox heberge des VMs sur un
> bridge isole qui n'a aucun acces au reste du LAN.

#### Installation

```bash
# Sur le Proxmox host (necessite internet, donc apres l'install sur le LAN)
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up
# Suivre le lien affiche pour connecter le noeud au compte Tailscale

# Sur le laptop admin
curl -fsSL https://tailscale.com/install.sh | sh   # ou https://tailscale.com/download
tailscale up
```

Verifier :

```bash
tailscale status        # Doit montrer le Proxmox en "active"
ping 100.x.x.x          # IP Tailscale du Proxmox
```

Free tier : 100 devices, 3 utilisateurs — largement suffisant.

### 0.5 Configurer le bridge isole pour K8s

Interface web Proxmox : Node → Network → Create → Linux Bridge

| Parametre | Valeur |
|-----------|--------|
| Name | `vmbr1` |
| IPv4/CIDR | `10.10.0.1/24` |
| Bridge ports | *(laisser vide = reseau interne uniquement)* |
| Comment | `K8s cluster isolated network` |

### 0.5b Configurer le NAT et DHCP pour vmbr1

Le bridge vmbr1 est isole (pas de port physique). Pour que les VMs aient
internet, le Proxmox host doit faire office de routeur NAT, avec un DHCP
pour distribuer les IPs aux VMs Talos.

```bash
# --- NAT : permettre aux VMs (vmbr1) de sortir sur internet via vmbr0 ---
echo 1 > /proc/sys/net/ipv4/ip_forward
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

iptables -t nat -A POSTROUTING -s 10.10.0.0/24 -o vmbr0 -j MASQUERADE
iptables -A FORWARD -i vmbr1 -o vmbr0 -j ACCEPT
iptables -A FORWARD -i vmbr0 -o vmbr1 -m state --state RELATED,ESTABLISHED -j ACCEPT

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

### 0.6 Telecharger l'ISO Talos

```bash
# Sur le Proxmox host
cd /var/lib/vz/template/iso/
wget https://github.com/siderolabs/talos/releases/download/v1.12.3/metal-amd64.iso
```

### 0.7 Installer les outils CLI (sur le laptop)

```bash
curl -sL https://talos.dev/install | sh
talosctl version --client

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/
```

---

## Phase 1 : Creer le cluster Talos sur Proxmox (jour 1-2)

### 1.1 Creer les VMs dans Proxmox

| VM | VMID | Role | vCPU | RAM | Disque | Reseau |
|----|------|------|------|-----|--------|--------|
| talos-cp1 | 100 | Control Plane | 4 | 8 GB | 60 GB | vmbr1 |
| talos-worker1 | 101 | Worker | 6 | 20 GB | 150 GB | vmbr1 |
| talos-worker2 | 102 | Worker | 6 | 20 GB | 150 GB | vmbr1 |

Pour chaque VM :
- OS : Other (Talos n'est pas dans la liste)
- Boot : CD-ROM (ISO Talos)
- Disque : VirtIO, format qcow2
- Reseau : vmbr1, modele VirtIO

Demarrer les 3 VMs. Talos affiche son IP sur la console. Les noter.

### 1.2 Generer et appliquer la configuration

```bash
talosctl gen config crypto-bot https://<IP_CP>:6443 \
  --output-dir _talos_config

talosctl apply-config --insecure \
  --nodes <IP_CP> \
  --file _talos_config/controlplane.yaml

talosctl apply-config --insecure \
  --nodes <IP_WORKER_1> \
  --file _talos_config/worker.yaml

talosctl apply-config --insecure \
  --nodes <IP_WORKER_2> \
  --file _talos_config/worker.yaml
```

### 1.3 Bootstrap

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

> **Sauvegarder `_talos_config/talosconfig` et `./kubeconfig` dans un endroit
> sur (gestionnaire de mots de passe, backup chiffre)** — ce sont les seuls
> moyens d'administrer le cluster. Les perdre sans backup impose de
> reconstruire les noeuds Talos depuis zero (pas de recuperation possible,
> Talos n'a pas de shell/SSH de secours).

---

## Phase 2 : Infra de base sur le cluster (jour 2-3)

### 2.1 MetalLB

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml

kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=90s
```

`metallb-config.yaml` :

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
```

```bash
kubectl apply -f metallb-config.yaml
```

### 2.2 Ingress NGINX Controller

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.0/deploy/static/provider/cloud/deploy.yaml

kubectl get svc -n ingress-nginx ingress-nginx-controller
# EXTERNAL-IP doit afficher une IP de la plage MetalLB
```

### 2.3 Storage : local-path-provisioner

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml

kubectl patch storageclass local-path \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Talos applique PodSecurity "baseline" par defaut : le provisioner cree des
# helper pods avec hostPath, bloques par "baseline". Passer le namespace en
# "privileged" :
kubectl label ns local-path-storage pod-security.kubernetes.io/enforce=privileged
```

> **Necessaire apres chaque reinstallation du cluster.** Sans ce label, les
> PVCs restent en `Pending`.

### 2.4 Creer les namespaces

```bash
kubectl create namespace staging
kubectl create namespace production
kubectl create namespace dev
```

### 2.5 Sealed Secrets

```bash
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.29.0/controller.yaml
kubectl get pods -n kube-system -l name=sealed-secrets-controller

# kubeseal CLI (Linux)
KUBESEAL_VERSION=0.29.0
curl -OL "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"
tar -xvzf kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
kubeseal --version
```

Usage pour chiffrer un secret :

```bash
kubectl create secret generic crypto-bot-secrets \
  --from-literal=POSTGRES_USER=postgres \
  --from-literal=POSTGRES_PWD=changeme \
  --dry-run=client -o yaml > secret.yaml

kubeseal --format=yaml < secret.yaml > sealed-secret.yaml
# sealed-secret.yaml peut etre commite dans Git en toute securite.
```

### 2.6 Monitoring : Loki + Promtail + Grafana

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

kubectl create namespace monitoring
kubectl label ns monitoring pod-security.kubernetes.io/enforce=privileged

helm install loki grafana/loki-stack \
  --namespace monitoring \
  --set grafana.enabled=true \
  --set loki.persistence.enabled=true \
  --set loki.persistence.size=5Gi \
  --version 2.10.3

kubectl get pods -n monitoring
# 5 attendus : loki-0, grafana, 3x promtail

kubectl get secret grafana-admin -n monitoring -o jsonpath="{.data.admin-password}" | base64 -d
kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80
# → http://localhost:3000, login : admin / <mot de passe ci-dessus>
```

> **Migration GitOps** : l'installation Helm manuelle ci-dessus est ensuite
> remplacee par une ArgoCD Application multi-source (`argocd/monitoring-app.yaml`).
> `helm uninstall loki -n monitoring` puis ArgoCD recree tout depuis Git.

---

## Phase 3 : Repo GitOps crypto-bot-infra (jour 3-5)

### 3.1 Creer le repo sur GitLab

Creer `crypto-bot-infra` sur GitLab (groupe `dst_crypto`).

### 3.2 Structure du repo

```
crypto-bot-infra/
├── base/                    # Ressources Kustomize communes (backend, frontend, postgres, minio)
├── overlays/
│   ├── dev/
│   ├── staging/
│   └── production/
├── monitoring/              # Extras monitoring (dashboards Grafana)
├── argocd/                  # Applications ArgoCD (staging/production/monitoring)
└── scripts/                 # verify.sh, rotate_secrets.sh, port-forward.sh
```

Voir le repo pour les manifests complets (base/, overlays/) — trop volumineux
pour etre reproduits ici, et ils evoluent independamment de ce runbook.

### 3.3 Applications ArgoCD

**argocd/staging-app.yaml** (auto-sync) :

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

**argocd/production-app.yaml** (sync manuel) :

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
    path: overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    # PAS de automated : sync manuel pour la prod
    syncOptions:
      - CreateNamespace=true
```

---

## Phase 4 : Installer ArgoCD (jour 5-6)

```bash
kubectl create namespace argocd

kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl wait --namespace argocd \
  --for=condition=available deployment \
  --all --timeout=300s

# Mot de passe initial
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

kubectl port-forward svc/argocd-server -n argocd 8443:443
# https://localhost:8443 — Login : admin / <mot de passe>
```

### Configurer le repo GitLab

```bash
argocd login localhost:8443 --insecure

argocd repo add https://gitlab.com/dst_crypto/crypto-bot-infra.git \
  --username gitlab-ci-token \
  --password <DEPLOY_TOKEN>
```

Deploy Token : GitLab > `crypto-bot-infra` > Settings > Repository > Deploy tokens,
scope `read_repository`.

### Deployer les Applications

```bash
kubectl apply -f argocd/staging-app.yaml
kubectl apply -f argocd/production-app.yaml
```

### ImagePullSecret

Necessaire dans chaque namespace pour pull les images du registry GitLab prive :

```bash
for NS in dev staging production; do
  kubectl create secret docker-registry gitlab-registry \
    --namespace $NS \
    --docker-server=registry.gitlab.com \
    --docker-username=<USERNAME_GITLAB> \
    --docker-password=<PERSONAL_ACCESS_TOKEN>
done
```

> Le password est un **Personal Access Token** (`glpat-...`, scope
> `read_registry`) — pas un deploy token (`gldt-...`).

---

## Phase 5 : Pipeline GitLab CI

Le pipeline CI ne deploie jamais directement sur le cluster (vrai GitOps
pull-based, voir [ARCHITECTURE.md](ARCHITECTURE.md) §2). Il met a jour un tag
d'image et une annotation dans `crypto-bot-infra`, et ArgoCD fait le reste.

Le job reel (`update:manifests`) vit dans `crypto-bot-app/.gitlab-ci.yml` —
voir ce fichier pour l'implementation exacte (elle evolue independamment de
ce runbook, mieux vaut lire le code source que le dupliquer ici). Le flux
complet (staging auto vs production taggee, anti-boucle sync submodules) est
documente dans [GIT_WORKFLOW.md](GIT_WORKFLOW.md).

---

## Phase 6 : Tunnel et reverse proxy

### 6.1 Cloudflare Tunnel (acces equipe)

```bash
kubectl create namespace cloudflare
# Configurer via Cloudflare Zero Trust dashboard :
# - Creer un tunnel
# - Associer les sous-domaines :
#   staging.crypto-bot.<domaine> → http://ingress-nginx.ingress-nginx:80
#   app.crypto-bot.<domaine>     → http://ingress-nginx.ingress-nginx:80
#   argocd.crypto-bot.<domaine>  → http://argocd-server.argocd:443
```

### 6.2 Tailscale (acces admin, sur les autres machines)

```bash
# Sur la VM AWS aussi
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up

# Tester depuis le laptop (avec Tailscale)
kubectl --server=https://<TAILSCALE_IP_CP>:6443 get nodes
```

### 6.3 Nginx reverse proxy sur la VM AWS

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

## Phase 7 : Backups et fallback

### 7.1 CronJob backup des bases (K8s → VM AWS)

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
                  apk add --no-cache postgresql-client openssh-client
                  pg_dump -h postgres -U postgres crypto_bot_db | gzip > /tmp/pg_backup.sql.gz
                  scp -i /secrets/ssh-key /tmp/*.gz ubuntu@<IP_VM_AWS>:/opt/backups/
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

### 7.2 Script de fallback sur la VM AWS

```bash
#!/bin/bash
# /opt/fallback.sh - A executer si le Proxmox tombe
echo "=== Activation du fallback ==="
cd /opt/crypto-bot-prod
gunzip -c /opt/backups/pg_backup.sql.gz | docker exec -i prod-postgres psql -U postgres crypto_bot_db
docker compose -f docker-compose.prod.yml up -d
cp /etc/nginx/conf.d/fallback.conf /etc/nginx/conf.d/default.conf
nginx -s reload
echo "=== Fallback actif (RPO max 6h) ==="
```

### 7.3 Script de retour a la normale

```bash
#!/bin/bash
# /opt/restore-normal.sh - Quand le Proxmox revient
echo "=== Retour au mode normal ==="
cp /etc/nginx/conf.d/tunnel.conf /etc/nginx/conf.d/default.conf
nginx -s reload
docker compose -f docker-compose.prod.yml down
echo "=== Mode normal retabli ==="
```

---

## Phase 8 : GitLab Runner self-hosted (optionnel)

Deployer un GitLab Runner sur le Proxmox ou dans le cluster K8s pour
executer les pipelines CI/CD en local plutot que via les shared runners
GitLab.com (builds plus rapides, pas de limite de minutes CI/CD).

```bash
# Option A : Runner Docker sur le Proxmox host (VM/LXC dediee)
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

> Token : GitLab > Groupe `dst_crypto` > Settings > CI/CD > Runners > New group runner.

---

## Phase 9 : Maintenance — nettoyage Docker automatique (tout hote)

**A faire sur chaque hote qui execute des `docker build`/`docker compose up`
regulierement** : le runner GitLab (Phase 8), les VMs AWS staging/production
(docker-compose), tout hote Proxmox qui buildrait des images en local. Sans ca, les
images/layers/build-cache s'accumulent en silence jusqu'a `no space left on device` —
deja rencontre deux fois (runner GitLab le 2026-07-21, VM staging le 2026-07-23, dans les
deux cas suite a une accumulation de mois de builds jamais nettoyes).

```bash
# 1. Script de nettoyage (necessite sudo si /usr/local/bin est root-owned)
cat << 'EOF' | sudo tee /usr/local/bin/docker-prune-weekly.sh > /dev/null
#!/bin/sh
set -eu
LOG=/var/log/docker-prune.log
{
  echo "=== $(date -Is) ==="
  docker system prune -af --volumes
  docker builder prune -af
  echo '--- espace disque apres nettoyage ---'
  df -h /
} >> "$LOG" 2>&1
EOF
sudo chmod +x /usr/local/bin/docker-prune-weekly.sh

# 2. Cron hebdomadaire (dimanche 3h — passer a quotidien si les builds
#    s'accumulent plus vite que prevu)
(crontab -l 2>/dev/null; echo '0 3 * * 0 /usr/local/bin/docker-prune-weekly.sh') | crontab -

# 3. Verification
crontab -l
cat /usr/local/bin/docker-prune-weekly.sh
```

Le log `/var/log/docker-prune.log` permet de confirmer apres coup que le cron tourne bien
chaque semaine (`docker system prune -af --volumes` supprime aussi les conteneurs arretes
et volumes orphelins — sans danger sur un hote CI/deploiement sans etat persistant en
dehors des volumes nommes de l'application elle-meme, qui ne sont pas touches tant qu'un
service les utilise).

---

## Verification et checklists

### Checklist Phase 0-1 : Proxmox + Cluster Talos

- [ ] Bridge isole `vmbr1` cree sur Proxmox
- [ ] ISO Talos telecharge sur le Proxmox
- [ ] talosctl et kubectl installes
- [ ] 3 VMs creees (CP 8GB + 2 Workers 20GB)
- [ ] Config Talos generee et appliquee
- [ ] Cluster bootstrap reussi
- [ ] `kubectl get nodes` = 3 noeuds Ready
- [ ] `_talos_config/talosconfig` et `kubeconfig` sauvegardes en lieu sur

### Checklist Phase 2-3 : Infra K8s + GitOps

- [ ] MetalLB installe (plage 10.10.0.240-250)
- [ ] Ingress NGINX installe
- [ ] local-path-provisioner installe + label PodSecurity sur `local-path-storage`
- [ ] Sealed Secrets controller installe (ns kube-system) + kubeseal CLI local
- [ ] Loki + Promtail + Grafana installes (ns monitoring) + label PodSecurity
- [ ] Namespaces dev + staging + production crees
- [ ] Repo `crypto-bot-infra` complete (tous les YAML remplis)

### Checklist Phase 4-5 : ArgoCD + Pipeline

- [ ] ArgoCD installe, UI accessible
- [ ] Repo GitLab connecte a ArgoCD (deploy token)
- [ ] Applications staging (auto-sync) + production (sync manuel) deployees
- [ ] Pipeline GitLab CI : `update:manifests` fonctionnel
- [ ] ImagePullSecrets crees dans les trois namespaces (dev, staging, production)

### Checklist Phase 6-7 : Tunnel + Fallback

- [ ] Cloudflare Tunnel operationnel (equipe accede via navigateur)
- [ ] Tailscale installe (admin accede a kubectl, ArgoCD UI, Grafana)
- [ ] Nginx reverse proxy configure sur la VM AWS
- [ ] CronJob backup toutes les 6h (PostgreSQL → VM AWS)
- [ ] Script fallback.sh teste (docker-compose demarre + Nginx bascule)
- [ ] Script restore-normal.sh teste

### Checklist Securite

- [ ] VMs K8s sur bridge isole (vmbr1), pas d'acces au LAN
- [ ] SSH par cle uniquement sur Proxmox
- [ ] RBAC K8s configure (roles par namespace)
- [ ] Sealed Secrets installe (pas de secrets en clair dans Git)
- [ ] NetworkPolicies deployees (non enforcees sans policy controller, voir ARCHITECTURE.md §5)
- [ ] Containers non-root

---

## Ressources utiles

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
