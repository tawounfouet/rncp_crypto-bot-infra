# Monitoring — Grafana / Prometheus / VM AWS

> Pour l'architecture generale, voir [ARCHITECTURE.md](ARCHITECTURE.md#5-architecture-cible).
> Pour l'acces reseau (Tailscale, port-forward), voir [ONBOARDING.md](ONBOARDING.md).

## Vue d'ensemble

Un seul Grafana (namespace `monitoring`, deploye via ArgoCD) centralise l'etat des
**5 environnements** du projet :

| Environnement | Source | Ce qu'on voit |
|---|---|---|
| `dev` (K8s) | Prometheus in-cluster (dashboard "Infra K8s") | CPU/RAM/etat des pods |
| `staging` (K8s) | Prometheus in-cluster + Promtail K8s (logs) | CPU/RAM/etat des pods + logs |
| `production` (K8s) | Prometheus in-cluster + Promtail K8s (logs) | CPU/RAM/etat des pods + logs |
| VM AWS Liora (staging/prod fallback) | Promtail sur la VM (logs, `{source="vm-aws"}`) | Logs staging/prod, distincts des logs K8s |
| VM AWS Liora (metriques CPU/RAM/etat) | node_exporter + blackbox-exporter | **Prepares mais non fonctionnels**, voir limite ci-dessous |

> **Limite connue** : `node_exporter`/`blackbox-exporter` sur la VM sont installes/configures
> (cf. section dediee plus bas) mais **Prometheus in-cluster ne peut pas les scraper** :
> les pods K8s n'ont pas d'interface Tailscale (contrairement aux logs, qui partent
> de la VM *vers* le cluster via l'ingress — sens inverse, ca marche). Pas de fix
> retenu avant la soutenance (options : pod sidecar Tailscale, operateur K8s officiel).
> Etat de la VM verifiable manuellement : `tailscale ping vm-liora-crypto-bot`,
> ou `curl http://100.x.x.x:9100/metrics` depuis un poste sur le tailnet.

Utilisateurs enregistres / etat DB : requetes directes sur les Postgres de chaque
environnement (datasource Postgres native de Grafana, ou requete SQL manuelle —
voir [ONBOARDING.md §4](ONBOARDING.md#4-consulter-les-secrets-mots-de-passe-bdd-cles-api)
pour recuperer les credentials).

## Acces

Via port-forward (voir [ONBOARDING.md](ONBOARDING.md#acces-aux-services-app--bases-de-donnees)) :

```bash
./scripts/port-forward.sh infra
```

- Grafana : http://localhost:3000
- Prometheus (debug direct, pas indispensable au quotidien) :
  ```bash
  kbot port-forward -n monitoring svc/monitoring-prometheus-server 9090:80
  ```
  puis http://localhost:9090/targets pour verifier l'etat des cibles de scrape.

## Ce qui est deploye (namespace `monitoring`)

Tout passe par le chart Helm `loki-stack` (deja utilise pour Loki/Promtail/Grafana),
etendu avec son sous-chart `prometheus` (bundle historique : prometheus-server +
node-exporter + kube-state-metrics), plus un chart separe `prometheus-blackbox-exporter`.
Voir `argocd/monitoring-app.yaml`.

- **prometheus-server** : scrape et stocke (retention 15j, PVC 8Gi `local-path`)
- **kube-state-metrics** : etat des pods/deploiements des 3 namespaces `dev`/`staging`/`production`
- **node-exporter** (DaemonSet, 3 nœuds Talos, tolerations control-plane incluses) : CPU/RAM des machines physiques du cluster
- **blackbox-exporter** : sondes HTTP a la demande (pas de metriques propres, cf. ci-dessous)
- alertmanager et pushgateway sont **desactives** (pas necessaires pour un dashboard de suivi, economise de la RAM)

Le datasource Grafana "Prometheus" est cree automatiquement par le sidecar de
datasources du chart (deja actif pour Loki) des que `prometheus.enabled: true` —
aucune config manuelle cote Grafana.

## VM AWS Liora — monitoring du fallback

La VM AWS ne tourne pas en permanence les 2 stacks (staging + prod) — RAM limitee
(7.6 Go), voir [ARCHITECTURE.md](ARCHITECTURE.md). L'objectif du monitoring ici
n'est pas la profondeur (pas de per-container comme sur K8s) mais 3 signaux
independants :

1. **La VM est vivante** (peu importe l'etat des apps) : `node_exporter` tourne en
   **service systemd natif**, hors des projets docker-compose — un `docker compose down`
   sur staging ou prod ne l'arrete pas.
2. **App staging up/down**
3. **App prod up/down**

(2) et (3) sont sondes independamment de (1) : si un fond de conteneur plante, on
distingue clairement "la machine a un probleme" de "juste une des deux apps".

### node_exporter (sur la VM, une seule fois)

Installe en systemd natif (pas Docker) — reference version : `v1.8.2` (memes
`versions.env` que le monitoring dev local, cf. `crypto-bot-app/monitoring/`).

```bash
# User dedie, sans privileges (pas de shell)
sudo useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter

# Telechargement + verification du checksum (toujours verifier un binaire tiers)
cd /tmp
curl -LO https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz
curl -LO https://github.com/prometheus/node_exporter/releases/download/v1.8.2/sha256sums.txt
sha256sum --ignore-missing -c sha256sums.txt   # doit afficher "OK"

tar xzf node_exporter-1.8.2.linux-amd64.tar.gz
sudo mv node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/
sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter
```

Service systemd (`/etc/systemd/system/node_exporter.service`) :

```ini
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
sudo systemctl status node_exporter   # doit afficher "active (running)"
curl -s http://localhost:9100/metrics | head -5   # verif locale
```

Reachable uniquement via Tailscale (`100.100.226.42:9100` au moment de l'ecriture,
verifier l'IP actuelle avec `tailscale status`), **pas** expose publiquement — voir
[ONBOARDING.md §VM AWS Liora sur le tailnet](ONBOARDING.md#vm-aws-liora-sur-le-tailnet).

### blackbox-exporter (in-cluster) — sondes `/health`

Contrairement a node_exporter, blackbox-exporter n'a pas ses propres metriques : on
lui demande "va verifier CETTE url", via son endpoint special `/probe`. Config dans
`argocd/monitoring-app.yaml`, cle `prometheus.extraScrapeConfigs` (doit etre une
**chaine de texte** avec `|`, pas une liste YAML native — c'est le format attendu
par le chart `prometheus` sous-jacent) :

```yaml
- job_name: blackbox
  metrics_path: /probe
  params:
    module: [http_2xx]
  static_configs:
    - targets:
      - http://100.100.226.42:8009/health   # staging
      - http://100.100.226.42:8010/health   # prod
  relabel_configs:
    - source_labels: [__address__]
      target_label: __param_target
    - source_labels: [__param_target]
      target_label: instance
    - target_label: __address__
      replacement: monitoring-prometheus-blackbox-exporter:9115
```

Le `relabel_configs` en 3 etapes est le point le moins intuitif : `targets` donne
d'abord l'URL a tester (traitee par erreur comme adresse a scraper), puis on la
recopie en parametre `?target=` (etape 1) et en label `instance` pour la lisibilite
(etape 2), avant de remplacer l'adresse reelle a contacter par celle du service
blackbox-exporter lui-meme (etape 3) — c'est lui qui fait la requete HTTP, pas
Prometheus directement.

> Le nom exact du service (`monitoring-prometheus-blackbox-exporter`) suit la
> convention Helm `<release>-<chart>` — a **verifier** apres sync plutot qu'a deviner :
> `kbot get svc -n monitoring | grep blackbox`.

Ports staging/prod sur la VM : `docker-compose.staging.yml` (backend `:8009`) et
`docker-compose.prod.yml` (backend `:8010`).

## Piege rencontre — `ALLOWED_HOSTS` et les probes/sondes

`TrustedHostMiddleware` (backend FastAPI) verifie le header `Host` de **toute**
requete, y compris `/health`. Deux consommateurs de `/health` envoient un `Host`
qui n'est pas une URL "normale" :

- **kubelet** (probes K8s) : appelle le pod par IP directe, sans nom DNS.
- **blackbox-exporter** : envoie l'IP/port de la cible sondee.

Sans le bon `Host` dans `ALLOWED_HOSTS`, ces deux verifications recoivent un `400`
au lieu d'un `200` → CrashLoopBackOff (probes K8s) ou faux "down" (blackbox).

Fix applique :
- **Probes K8s** (`base/backend/deployment.yaml`) : `httpHeaders` force le `Host`
  vers une valeur deja whitelistee (`crypto-bot-backend`), plutot que d'ouvrir
  `ALLOWED_HOSTS` a `*`.
- **VM AWS** : l'IP Tailscale de la VM (`100.100.226.42`) a ete ajoutee a
  `ALLOWED_HOSTS`/`MLFLOW_SERVER_ALLOWED_HOSTS` dans `.env` sur la VM (a cote de
  l'IP publique deja presente) — sinon blackbox recoit aussi un 400.

## Logs de la VM AWS (Promtail → Loki)

Sens inverse du probleme metriques ci-dessus : ici c'est la VM qui **pousse** vers
le cluster, pas le cluster qui scrape la VM — ca marche, a condition que la VM
route vers `10.10.0.0/24` (meme route de subnet que pour joindre l'API K8s).

### 1. Exposer Loki (cote cluster, deja fait)

`monitoring/loki-ingress.yaml` route `loki.crypto-bot.local` (meme IP MetalLB que
les autres ingress, `10.10.0.240`) vers `monitoring-loki:3100`. Pas d'authn sur ce
endpoint : acceptable uniquement parce que seul le tailnet prive y accede (voir le
commentaire dans le fichier avant de reutiliser ce pattern ailleurs).

### 2. Sur la VM AWS

```bash
# Accepter la route vers le cluster (comme pour tout nouveau device tailnet)
sudo tailscale set --accept-routes=true

# Verifier
curl -H "Host: loki.crypto-bot.local" http://10.10.0.240/ready   # doit repondre "ready"

# Resolution DNS locale (lisibilite de la config Promtail)
echo "10.10.0.240 loki.crypto-bot.local" | sudo tee -a /etc/hosts
```

Config Promtail (`/opt/promtail-config.yml`) — decouverte automatique des
conteneurs Docker, avec extraction de `environment` (`staging`/`prod`) depuis le
prefixe du nom de conteneur (`staging-backend`, `prod-backend`, ...) :

```yaml
server:
  http_listen_port: 9080
positions:
  filename: /tmp/positions.yaml
clients:
  - url: http://loki.crypto-bot.local/loki/api/v1/push
scrape_configs:
  - job_name: docker
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 5s
    relabel_configs:
      - source_labels: ['__meta_docker_container_name']
        regex: '/(staging|prod)-.*'
        target_label: 'environment'
        replacement: '$1'
      - source_labels: ['__meta_docker_container_name']
        regex: '/(.*)'
        target_label: 'container'
      - target_label: 'source'
        replacement: 'vm-aws'
```

```bash
docker run -d --name promtail --restart=always \
  --add-host=loki.crypto-bot.local:10.10.0.240 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v /opt/promtail-config.yml:/etc/promtail/config.yml:ro \
  -v promtail-positions:/tmp \
  grafana/promtail:3.5.1 -config.file=/etc/promtail/config.yml
```

> **Piege** : `--add-host` est indispensable. Le conteneur Docker a son propre
> resolveur DNS, il ne lit **pas** le `/etc/hosts` de la VM — sans ce flag, erreur
> `dial tcp: lookup loki.crypto-bot.local ... no such host` malgre l'entree hosts
> ajoutee cote VM.

### Distinguer les logs VM vs K8s dans Grafana/Loki

- Logs K8s (Promtail in-cluster, auto-label) : `{namespace="staging"}`
- Logs VM AWS (Promtail sur la VM, labels manuels) : `{source="vm-aws", environment="staging"}`

Jamais melanges — deux jeux de labels distincts par construction.

## Piege rencontre — `argocd/*.yaml` pas auto-applique

Voir [ARCHITECTURE.md — App-of-apps](ARCHITECTURE.md#gitops-avec-argocd) : pousser
une modif de `argocd/monitoring-app.yaml` sur `main` ne suffisait pas avant
`root-app` — il fallait un `kubectl apply -f argocd/monitoring-app.yaml` manuel en
plus. Resolu par le pattern app-of-apps (`root-app` surveille `argocd/`).
