# Onboarding Equipe — Acces au Cluster Kubernetes

## Prerequis

Chaque membre de l'equipe doit installer **kubectl** et disposer du **kubeconfig** + acces SSH au Proxmox.

---

## 1. Installer kubectl

### Linux / WSL2

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version --client
```

### macOS

```bash
# Avec Homebrew
brew install kubectl

# Ou manuellement (Apple Silicon)
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/arm64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

### Windows (PowerShell)

```powershell
# Avec Chocolatey
choco install kubernetes-cli

# Ou manuellement
curl.exe -LO "https://dl.k8s.io/release/v1.32.2/bin/windows/amd64/kubectl.exe"
# Deplacer kubectl.exe dans un dossier du PATH
```

---

## 2. Configurer l'acces SSH au Proxmox

Le cluster K8s tourne sur un reseau isole (10.10.0.0/24) derriere le serveur Proxmox.
Pour y acceder, on utilise un **tunnel SSH** a travers le Proxmox.

### 2.1 Generer une cle SSH (si pas deja fait)

```bash
ssh-keygen -t ed25519 -C "prenom@crypto-bot"
```

### 2.2 Envoyer la cle publique a l'admin

Envoie le contenu de `~/.ssh/id_ed25519.pub` a l'admin du cluster.
L'admin l'ajoutera sur le Proxmox pour te donner l'acces.

**Admin** — pour ajouter un membre (sur le Proxmox en root) :

```bash
# Creer un user (une seule fois par membre)
useradd -m -s /bin/bash <prenom>
mkdir -p /home/<prenom>/.ssh
echo '<CLE_PUBLIQUE_DU_MEMBRE>' > /home/<prenom>/.ssh/authorized_keys
chown -R <prenom>:<prenom> /home/<prenom>/.ssh
chmod 700 /home/<prenom>/.ssh
chmod 600 /home/<prenom>/.ssh/authorized_keys
```

### 2.3 Tester la connexion

```bash
ssh <ton_user>@192.168.250.241
# Doit se connecter sans mot de passe
```

> **Note** : le Proxmox doit etre accessible depuis ton reseau.
> Si tu es a distance (hors LAN entreprise), utilise Tailscale (voir section 5).

---

## 3. Se connecter au cluster

### 3.1 Recuperer le kubeconfig

Demande le fichier `kubeconfig` a l'admin du cluster. Place-le dans :

```bash
mkdir -p ~/.kube
# Copier le fichier kubeconfig fourni par l'admin
cp kubeconfig ~/.kube/kubeconfig_cryptobot.yaml
```

### 3.2 Acces reseau au cluster

Le cluster K8s est sur un reseau isole (10.10.0.0/24) derriere le Proxmox.

**Methode principale — Tailscale (recommande)** :

1. Installe Tailscale : https://tailscale.com/download
2. Connecte-toi au tailnet de l'equipe (demande l'invitation a l'admin)
3. Active l'acceptation des routes : `tailscale up --accept-routes`
4. Le reseau 10.10.0.0/24 est directement accessible, pas besoin de tunnel

**Methode alternative — Tunnel SSH (si pas de Tailscale)** :

```bash
ssh -L 6443:10.10.0.125:6443 -N <ton_user>@192.168.250.241
```

> Lance cette commande dans un terminal dedie (elle reste ouverte).
> `-N` = pas de shell, juste le tunnel.
> Avec cette methode, remplace `10.10.0.125` par `127.0.0.1` dans le kubeconfig.

### 3.3 Configurer kubectl

Ajoute dans ton `~/.bashrc` ou `~/.zshrc` :

```bash
export KUBECONFIG="$HOME/.kube/kubeconfig_cryptobot.yaml"
alias kbot='kubectl --context admin@crypto-bot'
```

Recharge le shell :

```bash
source ~/.bashrc  # ou source ~/.zshrc
```

### 3.4 Tester

```bash
kbot get nodes
# Attendu : 3 noeuds Ready
```

---

## 4. Consulter les secrets (mots de passe BDD, cles API)

Les secrets sont chiffres dans Git (Sealed Secrets) mais dechiffres dans le cluster.
Pour lire un secret :

### Lister les secrets d'un namespace

```bash
kbot get secrets -n staging
kbot get secrets -n production
```

### Voir les valeurs d'un secret

```bash
# Staging — tous les secrets de l'appli
kbot get secret crypto-bot-secrets -n staging -o jsonpath='{.data}' | python3 -c "
import sys, json, base64
data = json.loads(sys.stdin.read())
for k, v in sorted(data.items()):
    print(f'{k} = {base64.b64decode(v).decode()}')
"
```

### Voir une seule valeur

```bash
# Exemple : mot de passe PostgreSQL staging
kbot get secret crypto-bot-secrets -n staging \
  -o jsonpath='{.data.POSTGRES_PWD}' | base64 -d && echo
```

### Raccourci : alias utiles

Ajoute dans ton `~/.bashrc` ou `~/.zshrc` :

```bash
# Voir tous les secrets staging
alias kbot-secrets-staging='kbot get secret crypto-bot-secrets -n staging -o jsonpath="{.data}" | python3 -c "import sys,json,base64; data=json.loads(sys.stdin.read()); [print(f\"{k} = {base64.b64decode(v).decode()}\") for k,v in sorted(data.items())]"'

# Voir tous les secrets production
alias kbot-secrets-prod='kbot get secret crypto-bot-secrets -n production -o jsonpath="{.data}" | python3 -c "import sys,json,base64; data=json.loads(sys.stdin.read()); [print(f\"{k} = {base64.b64decode(v).decode()}\") for k,v in sorted(data.items())]"'
```

---

## 5. Acces reseau — Details Tailscale

Tailscale est installe sur le Proxmox et annonce le subnet `10.10.0.0/24`.
Cela permet d'acceder directement aux noeuds K8s et aux IPs MetalLB depuis
n'importe quel appareil connecte au tailnet, sans tunnel SSH.

Configuration sur le Proxmox (deja fait, a refaire si reinstallation) :
```bash
tailscale up --advertise-routes=10.10.0.0/24 --accept-routes
```

Configuration sur chaque poste client :
```bash
tailscale up --accept-routes
```

Puis approuver les routes dans la console Tailscale (login.tailscale.com → Machines → pve1 → Edit route settings).

---

## 6. Modifier un secret (kubeseal)

Pour ajouter ou modifier un secret, il faut **kubeseal** (le secret doit etre chiffre avant d'etre commite dans Git).

### Installer kubeseal

```bash
# Linux / WSL2
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.29.0/kubeseal-0.29.0-linux-amd64.tar.gz
tar xzf kubeseal-0.29.0-linux-amd64.tar.gz
sudo mv kubeseal /usr/local/bin/
rm kubeseal-0.29.0-linux-amd64.tar.gz

# macOS (Homebrew)
brew install kubeseal
```

### Modifier un secret

```bash
# 1. Creer le secret en clair dans un fichier temporaire
cat > /tmp/secret.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: crypto-bot-secrets
  namespace: staging
type: Opaque
stringData:
  MA_NOUVELLE_CLE: "ma_nouvelle_valeur"
EOF

# 2. Chiffrer avec kubeseal (le tunnel SSH doit etre actif)
kubeseal --controller-namespace kube-system \
  --format yaml \
  < /tmp/secret.yaml \
  > overlays/staging/secrets.yaml

# 3. Supprimer le fichier en clair
rm /tmp/secret.yaml

# 4. Commiter le SealedSecret (chiffre, safe pour Git)
git add overlays/staging/secrets.yaml
git commit -m "chore: update staging secrets"
git push
```

---

## 7. Workflow de developpement (namespace dev)

Le namespace `dev` permet de tester ses changements sur le cluster K8s **sans MR ni pipeline CI**.

### Principe

```
docker-compose (local)     →  dev rapide sur ton laptop
dev-deploy.sh (cluster)    →  test sur le vrai cluster K8s (namespace dev)
MR → staging (CI)          →  deploiement staging automatique
Tag vX.X → production (CI) →  deploiement production manuel
```

### Prerequis (une seule fois)

```bash
# Se connecter au registry GitLab
docker login registry.gitlab.com
# Username : ton user GitLab
# Password : Personal Access Token (scopes read_registry + write_registry)
```

### Deployer sur le namespace dev

Depuis la racine du repo `Crypto-bot/` :

```bash
# Tout builder et deployer (backend + frontend)
./scripts/dev-deploy.sh

# Juste le backend (quand tu ne touches pas au frontend)
./scripts/dev-deploy.sh backend

# Juste le frontend
./scripts/dev-deploy.sh frontend
```

Le script fait 3 choses :
1. Build l'image Docker localement
2. Push sur le registry avec le tag `:dev`
3. Restart les pods dans le namespace dev

### Acceder a l'app sur le namespace dev

```bash
# Port-forward le frontend
kbot port-forward -n dev svc/crypto-bot-frontend 8501:8501
# Ouvrir http://localhost:8501

# Port-forward le backend (API)
kbot port-forward -n dev svc/crypto-bot-backend 8009:8009
# Tester http://localhost:8009/health
```

### Voir les logs dev

```bash
kbot logs -n dev deployment/crypto-bot-backend -f
kbot logs -n dev deployment/crypto-bot-frontend -f
```

### Les 3 namespaces

| Namespace | Tag image | Comment deployer | ArgoCD |
|-----------|-----------|-----------------|--------|
| `dev` | `:dev` | `./scripts/dev-deploy.sh` (manuel) | Non |
| `staging` | `:staging` | Push sur branche `staging` → CI auto | Auto-sync |
| `production` | `:production` | Tag `vX.X` → CI + sync manuel | Manuel |

---

## 8. Commandes utiles

```bash
# Etat du cluster
kbot get nodes                          # Noeuds
kbot get pods -n staging                # Pods staging
kbot get pods -n production             # Pods production
kbot get svc -n staging                 # Services staging
kbot get pvc -n staging                 # Volumes persistants

# Logs d'un pod
kbot logs -n staging deployment/crypto-bot-backend
kbot logs -n staging deployment/crypto-bot-frontend -f   # -f = follow (temps reel)

# Debug un pod qui crashe
kbot describe pod -n staging <nom-du-pod>
kbot logs -n staging <nom-du-pod> --previous   # Logs du crash precedent

# Redemarrer un deployment
kbot rollout restart deployment/crypto-bot-backend -n staging

# Port-forward pour acceder a un service localement
kbot port-forward -n staging svc/crypto-bot-frontend 8501:8501
# Puis ouvrir http://localhost:8501
```

---

## Acces aux services (app + bases de donnees)

Tous les services du cluster sont en ClusterIP (pas d'acces direct depuis l'exterieur).
Pour y acceder depuis votre poste, utilisez le **port-forward**.

### Script tout-en-un

Un script lance tous les port-forwards d'un namespace en une seule commande :

```bash
# Dev (par defaut)
./scripts/port-forward.sh

# Staging
./scripts/port-forward.sh staging

# Production
./scripts/port-forward.sh production
```

Ctrl+C arrete tous les port-forwards d'un coup.
Chaque environnement utilise des ports locaux differents, ce qui permet de lancer
plusieurs environnements en parallele (un terminal par environnement).

| Service | Dev | Staging | Production |
|---------|-----|---------|------------|
| Frontend | localhost:8501 | localhost:8601 | localhost:8701 |
| Backend API | localhost:8009 | localhost:8109 | localhost:8209 |
| PostgreSQL | localhost:5432 | localhost:5532 | localhost:5632 |
| MongoDB | localhost:27017 | localhost:27117 | localhost:27217 |
| MinIO API | localhost:9000 | localhost:9100 | localhost:9200 |
| MinIO Console | localhost:9001 | localhost:9101 | localhost:9201 |

> **Note** : PostgreSQL et MongoDB ne sont **pas** des services HTTP.
> N'essayez pas d'y acceder via un navigateur — utilisez un client dedie.

### Port-forward manuel (un service a la fois)

```bash
# Remplacez dev par staging ou production selon l'environnement
kbot port-forward -n dev svc/crypto-bot-frontend 8501:8501
kbot port-forward -n dev svc/crypto-bot-backend 8009:8009
kbot port-forward -n dev svc/postgres 5432:5432
kbot port-forward -n dev svc/mongo 27017:27017
kbot port-forward -n dev svc/minio 9000:9000 9001:9001
```

### Connexion aux bases de donnees

**PostgreSQL** (`psql`, DBeaver, pgAdmin, DataGrip) :
```bash
psql -h 127.0.0.1 -p 5432 -U <POSTGRES_USER> -d crypto_bot_db
```

**MongoDB** (`mongo`, `mongosh`, Compass, Studio 3T) :
```bash
# mongo:4.4 utilise le client "mongo" (mongosh n'est pas inclus)
mongo -u <MONGODB_USER> -p <MONGODB_PWD> --authenticationDatabase admin 127.0.0.1:27017

# Si mongosh est installe localement
mongosh "mongodb://<MONGODB_USER>:<MONGODB_PWD>@127.0.0.1:27017/admin"
```

**MinIO** : ouvrir http://localhost:9001 (console web)

### Recuperer les credentials

```bash
kbot get secret -n dev crypto-bot-secrets -o jsonpath='{.data}' \
  | python3 -c "import sys,json,base64; d=json.load(sys.stdin); \
    [print(f'{k}: {base64.b64decode(v).decode()}') for k,v in d.items()]"
```

Les cles disponibles : `POSTGRES_USER`, `POSTGRES_PWD`, `MONGODB_USER`, `MONGODB_PWD`,
`MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY`, `SECRET_KEY`.

---

## Notes specifiques Talos Linux

Le cluster Talos a quelques particularites qui necessitent des ajustements :

### PodSecurity et local-path-provisioner

Talos applique la politique PodSecurity `baseline` par defaut sur tous les namespaces.
Le local-path-provisioner utilise des helper pods avec `hostPath`, ce qui est bloque par `baseline`.
Apres chaque reinstallation du cluster, il faut executer :

```bash
kubectl label ns local-path-storage pod-security.kubernetes.io/enforce=privileged
```

Sans cette commande, les PVCs resteront en `Pending`.

### MongoDB et AVX

Les CPUs des VMs Proxmox n'ont pas le support AVX, requis par MongoDB 5+.
Le cluster utilise donc `mongo:4.4` (configure dans `base/mongo/statefulset.yaml`).

### SecurityContext des bases de donnees

Les images officielles postgres et mongo demarrent en root pour initialiser les volumes
(chown), puis drop vers un user non-root. Les StatefulSets ont donc :
- `allowPrivilegeEscalation: true` (requis pour gosu/su)
- `capabilities.add: [CHOWN, FOWNER, SETUID, SETGID, DAC_OVERRIDE]`

Les images backend/frontend utilisent `USER app` (UID 1000), donc les deployments
specifient `runAsUser: 1000` et `runAsGroup: 1000` pour satisfaire `runAsNonRoot: true`.

---

## Resume

| Etape | Commande / Action |
|-------|-------------------|
| Installer kubectl | `curl -LO ...` (voir section 1) |
| Recevoir le kubeconfig | Demander a l'admin |
| Lancer le tunnel SSH | `ssh -L 6443:10.10.0.125:6443 -N user@192.168.250.241` |
| Tester | `kbot get nodes` |
| Voir les secrets | `kbot get secret crypto-bot-secrets -n staging ...` |
| Modifier un secret | Installer kubeseal, chiffrer, commiter |
| Deployer en dev | `./scripts/dev-deploy.sh` (depuis Crypto-bot/) |
| Acceder a l'app dev | `kbot port-forward -n dev svc/crypto-bot-frontend 8501:8501` |
