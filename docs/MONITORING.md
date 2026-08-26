# Monitoring — Grafana / Prometheus / VM AWS

> Pour l'architecture generale, voir [ARCHITECTURE.md](ARCHITECTURE.md#5-architecture-cible).
> Pour l'acces reseau (Tailscale, port-forward), voir [ONBOARDING.md](ONBOARDING.md).

## Vue d'ensemble

Un seul Grafana (namespace `monitoring`, deploye via ArgoCD) centralise l'etat des
**5 environnements** du projet :

| Environnement | Source | Ce qu'on voit |
|---|---|---|
| `dev` (K8s) | Prometheus in-cluster | CPU/RAM/etat des pods, version (si trackee, cf. plus bas) |
| `staging` (K8s) | Prometheus in-cluster + Promtail K8s + Postgres | CPU/RAM/etat/version des pods, logs, utilisateurs |
| `production` (K8s) | Prometheus in-cluster + Promtail K8s + Postgres | CPU/RAM/etat/version des pods, logs, utilisateurs |
| VM AWS Liora (staging/prod fallback) | Promtail sur la VM (logs, `{source="vm-aws"}`) | Logs staging/prod, distincts des logs K8s |
| VM AWS Liora (metriques) | node_exporter + cAdvisor + blackbox-exporter, via `tailscale-proxy` | CPU/RAM machine + par service, `/health` staging et prod independants |

Les pods K8s n'ont pas d'interface Tailscale par eux-memes : Prometheus et
blackbox-exporter atteignent la VM AWS via un pod dedie, `tailscale-proxy`
(namespace `monitoring`), qui rejoint le tailnet en mode proxy SOCKS5/HTTP
(`:1055`) — voir section dediee plus bas.

**Utilisateurs (inscrits/connectes)** : panel "Utilisateurs" du dashboard "Infra K8s",
datasources PostgreSQL natives (Dev/Staging/Production). **Ne couvre pas la VM AWS** :
PostgreSQL est un protocole TCP brut, `tailscale-proxy` ne route que du HTTP
(Infinity/blackbox) — cf. section dediee plus bas.

**Version deployee (K8s)** : lue depuis l'annotation `deployed-commit` (le sha reel,
pose par le job CI `update:manifests`) via `kube-state-metrics`, **pas** depuis
`/health` (qui renvoie une chaine hardcodee `"1.0.0"` cote code applicatif, sans
rapport avec le commit reellement deploye). `dev` n'a pas cette annotation (namespace
non gere par ArgoCD/kustomize, deploye via `dev-deploy.sh`) — le dashboard affiche
alors "non trackee (deploiement manuel)" plutot qu'un vide.

## Acces

**Sans kubectl** (equipe, demo) : http://grafana.crypto-bot.local — ingress sur la
meme IP MetalLB que le reste (`10.10.0.240`), ajouter l'entree `/etc/hosts` comme pour
les autres services (voir [ONBOARDING.md](ONBOARDING.md)). Grafana garde son propre
login (`admin` + secret `grafana-admin`).

**Via port-forward** (voir [ONBOARDING.md](ONBOARDING.md#acces-aux-services-app--bases-de-donnees)) :

```bash
./scripts/port-forward.sh infra
```

- Grafana : http://localhost:3000
- Prometheus (debug direct, pas indispensable au quotidien) :
  ```bash
  kbot port-forward -n monitoring svc/monitoring-prometheus-server 9090:80
  ```
  puis http://localhost:9090/targets pour verifier l'etat des cibles de scrape.

## Version Grafana et compatibilite des plugins

Le chart `loki-stack` epingle Grafana `10.3.3` par defaut — **trop ancien pour le
plugin Infinity** (utilise pour les tuiles etat+version des 5 environnements) :
erreur navigateur `SystemJS Error#7` au chargement de `react/jsx-runtime` (import
maps, requiert Grafana >=10.4.8 meme sur la plus ancienne version compatible du
plugin, 3.4.1). Verifie sur `grafana.com/api/plugins/yesoreyeram-infinity-datasource/versions`
avant de choisir : `grafana.image.tag: 11.3.1` (memes que le monitoring dev local) +
`plugins: [yesoreyeram-infinity-datasource 3.4.1]` (epingle, versions >=3.5 exigent
Grafana >=11.6).

## Ce qui est deploye (namespace `monitoring`)

Tout passe par le chart Helm `loki-stack` (deja utilise pour Loki/Promtail/Grafana),
etendu avec son sous-chart `prometheus` (bundle historique : prometheus-server +
node-exporter + kube-state-metrics), plus un chart separe `prometheus-blackbox-exporter`.
Voir `argocd/monitoring-app.yaml`.

- **prometheus-server** : scrape et stocke (retention 15j, PVC 8Gi `local-path`)
- **kube-state-metrics** : etat des pods/deploiements des 3 namespaces `dev`/`staging`/`production`,
  + annotation `deployed-commit` exposee via `metricAnnotationsAllowList: ["pods=[deployed-commit]"]`
  (l'annotation est posee sur le **pod template**, pas sur le Deployment — `pods=`, pas `deployments=`,
  premier essai infructueux avant de verifier avec `kubectl get pods ... -o jsonpath='{.metadata.annotations}'`)
- **node-exporter** (DaemonSet, 3 nœuds Talos, tolerations control-plane incluses) : CPU/RAM des machines physiques du cluster
- **blackbox-exporter** : sondes HTTP a la demande (pas de metriques propres, cf. ci-dessous)
- **tailscale-proxy** : pod qui rejoint le tailnet pour joindre la VM AWS (cf. section dediee)
- alertmanager et pushgateway sont **desactives** (pas necessaires pour un dashboard de suivi, economise de la RAM)

Le datasource Grafana "Prometheus" est cree automatiquement par le sidecar de
datasources du chart (deja actif pour Loki) des que `prometheus.enabled: true` —
aucune config manuelle cote Grafana. Le datasource "Infinity" et les 3 datasources
PostgreSQL (Dev/Staging/Production) sont provisionnes explicitement (cle `grafana.datasources`),
cf. sections dediees.

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

### cAdvisor (sur la VM, une seule fois) — detail CPU/RAM par service

```bash
docker run -d --name cadvisor --restart=always \
  --privileged \
  -v /:/rootfs:ro \
  -v /var/run:/var/run:ro \
  -v /sys:/sys:ro \
  -v /var/lib/docker/:/var/lib/docker:ro \
  -v /dev/disk/:/dev/disk:ro \
  -p 8081:8080 \
  gcr.io/cadvisor/cadvisor:v0.52.1
```

> **Piege 1 — port** : `:8080` est deja pris par Airflow sur cette VM (`docker run`
> echoue avec `port is already allocated`) — mappe sur `:8081` cote hote.
>
> **Piege 2 — version** : `v0.49.1` (celle utilisee pour le monitoring dev local,
> `crypto-bot-app/monitoring/`) echoue a resoudre les conteneurs sur cette VM
> (Ubuntu recent, cgroup v2 + systemd) : logs remplis de
> `failed getting container info for "/system.slice/docker-<id>.scope": unknown container`
> et aucune metrique `container_*` par service (seuls les cgroups systemd bruts
> apparaissent, `id="/system.slice/..."`, jamais `name="<service>"`). `v0.52.1`
> gere ce format nativement — verifie manuellement (`curl .../metrics | grep container_cpu`)
> avant de cabler le scrape Prometheus.

Scrape (meme mecanisme `proxy_url` que `node_exporter`, cible `:8081`) :

```yaml
- job_name: cadvisor_vm
  proxy_url: http://tailscale-proxy.monitoring.svc.cluster.local:1055
  metrics_path: /metrics
  static_configs:
    - targets: ["100.100.226.42:8081"]
```

Requetes dashboard : `container_cpu_usage_seconds_total{job="cadvisor_vm", name!=""}` /
`container_memory_working_set_bytes{job="cadvisor_vm", name!=""}`, label `name`
directement lisible (`promtail`, `staging-backend`, `staging-frontend`, ...).

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
  `ALLOWED_HOSTS`/`MLFLOW_SERVER_ALLOWED_HOSTS` dans **`.env.staging`** (pas `.env` !)
  sur la VM, a cote de l'IP publique deja presente.

> **Piege** : le job CI `deploy:staging` fait `cp .env.staging .env` a **chaque**
> deploiement automatique (chaque push sur `staging`). Un edit fait uniquement sur
> `.env` est donc ecrase au prochain deploiement — vecu en pratique : le fix
> `ALLOWED_HOSTS` a ete perdu apres un merge qui a redeclenche `deploy:staging`.
> Toujours editer `.env.staging` (le template persistant) pour qu'un changement
> survive aux deploiements futurs.

## Joindre la VM AWS depuis le cluster (pod `tailscale-proxy`)

Les pods K8s n'ont pas d'interface Tailscale — sans ca, Prometheus et
blackbox-exporter ne peuvent pas atteindre `100.100.226.42` malgre la route de
subnet approuvee (qui ne beneficie qu'aux postes/laptops et a la VM elle-meme,
de vrais membres du tailnet). `monitoring/tailscale-proxy.yaml` deploie un pod
qui rejoint lui-meme le tailnet et expose un proxy SOCKS5/HTTP sur `:1055`,
utilise via `proxy_url` :

- **Prometheus** (`extraScrapeConfigs`, job `node_exporter`) : `proxy_url` au
  niveau du job -- c'est Prometheus lui-meme qui doit sortir vers la VM.
- **blackbox-exporter** (`config.modules.http_2xx.http.proxy_url`) : **pas**
  dans le job Prometheus du job `blackbox` (celui-la n'appelle que
  blackbox-exporter, deja joignable in-cluster) -- c'est blackbox-exporter
  lui-meme qui fait l'appel HTTP reel vers la VM, donc le proxy se configure
  dans son propre module, pas cote Prometheus.

Config notable :
- `TS_USERSPACE=true` : pas de TUN device / `NET_ADMIN` requis (conteneur non
  privilegie, compatible PodSecurity Talos).
- `TS_KUBE_SECRET=""` : **indispensable**. Sans ca, l'image `tailscale/tailscale`
  detecte qu'elle tourne sur K8s et tente par defaut de stocker son etat dans un
  Secret Kubernetes (`get`/`update` RBAC non accorde ici) plutot que d'utiliser
  `TS_STATE_DIR` (volume `emptyDir`) -> `CrashLoopBackOff` au demarrage sans ce
  flag.
- Cle d'auth (`TS_AUTHKEY`) generee en mode Reusable + Ephemeral depuis
  https://login.tailscale.com/admin/settings/keys, scellee comme les autres
  secrets (kubeseal).

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

## Utilisateurs inscrits/connectes (datasources PostgreSQL)

3 datasources PostgreSQL natives (Dev/Staging/Production, `argocd/monitoring-app.yaml`
cle `grafana.datasources`), identifiants charges via `envFromSecret: grafana-postgres-creds`
(SealedSecret, `monitoring/grafana-postgres-creds-sealed.yaml`) et interpoles dans le
provisioning avec la syntaxe `$VAR_NAME` (supportee nativement par Grafana) — **jamais**
de mot de passe en clair dans `argocd/monitoring-app.yaml`.

Requete type (panel "Utilisateurs", une target par environnement, transform `merge`) :
```sql
SELECT 'staging' AS environnement,
  (SELECT count(*) FROM users) AS inscrits,
  (SELECT count(*) FROM user_sessions WHERE expires_at > now()) AS connectes
```

**VM AWS non couverte** : contrairement a `node_exporter`/`cAdvisor`/blackbox-exporter
(HTTP, routables via `tailscale-proxy`), le driver PostgreSQL de Grafana parle un
protocole **TCP brut** que `tailscale-proxy` (mode SOCKS5/HTTP) ne sait pas relayer
nativement pour ce type de datasource — limitation distincte de celle deja resolue
pour les metriques/logs, non retenue avant la soutenance.

## Piege rencontre — `argocd/*.yaml` pas auto-applique (et sa propagation)

Voir [ARCHITECTURE.md — App-of-apps](ARCHITECTURE.md#gitops-avec-argocd) : pousser
une modif de `argocd/monitoring-app.yaml` sur `main` ne suffisait pas avant
`root-app` — il fallait un `kubectl apply -f argocd/monitoring-app.yaml` manuel en
plus. Resolu par le pattern app-of-apps (`root-app` surveille `argocd/`).

> **Piege residuel** : meme avec `root-app`, un `argocd.argoproj.io/refresh=hard`
> sur l'app `monitoring` juste apres un push peut ne rien changer si **`root-app`
> lui-meme** n'a pas encore relu son propre dossier `argocd/` (son polling a son
> propre rythme, independant du push). Verifiable via
> `kbot get application root-app -n argocd -o jsonpath='{.status.sync.revision}'`
> (doit matcher le dernier commit) — si perime, rafraichir `root-app` **avant**
> `monitoring` :
> ```bash
> kbot annotate application root-app -n argocd argocd.argoproj.io/refresh=hard --overwrite
> # attendre quelques secondes, puis
> kbot annotate application monitoring -n argocd argocd.argoproj.io/refresh=hard --overwrite
> ```
> Vecu en pratique plusieurs fois : `monitoring` affichait "Synced" mais sur une
> revision git perimee (`status.sync.revisions`), le changement n'atteignait jamais
> les pods tant que `root-app` n'etait pas rafraichi en premier.
