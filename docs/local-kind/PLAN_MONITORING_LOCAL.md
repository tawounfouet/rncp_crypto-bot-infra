# Plan d'implémentation — Monitoring local (Prometheus + Grafana) sur Kind

> Objet : rendre **Prometheus + Grafana** accessibles en local (cluster Kind `crypto-bot`),
> pour observer le namespace `dev` (pods backend/frontend/postgres/minio).
> Complément de [REMEDIATION_KIND_INFRA.md](./REMEDIATION_KIND_INFRA.md) et
> [DEPLOIEMENT_KIND_INFRA.md](./DEPLOIEMENT_KIND_INFRA.md).

## 1. Contexte

Le monitoring du projet n'existe que sur le **cluster distant** via ArgoCD
(`crypto-bot-infra/argocd/monitoring-app.yaml`) : chart `grafana/loki-stack` + sous-chart
`prometheus` + `prometheus-blackbox-exporter`, namespace `monitoring`. Il est **absent**
du Kind local et n'est pas déployable tel quel (ArgoCD absent, **SealedSecrets**
indéchiffrables, `tailscale-proxy` exige un tailnet, cibles VM AWS).

Recon effectuée (2026-10-07) :
- `helm` v4.2.0 présent, repos `prometheus-community` et `grafana` déjà ajoutés ;
- chart `kube-prometheus-stack` disponible (dernière : `92.1.0`, app `v0.94.1`) ;
- nœud Kind : 14 CPU, ~47 GiB RAM allouables → largement suffisant ;
- pas de metrics-server sur Kind (sans importance : `kube-prometheus-stack` scrape
  cAdvisor/kubelet + `kube-state-metrics` + `node-exporter`) ;
- l'app backend **n'expose pas `/metrics`** → on monitorera les objets K8s, pas l'API.

## 2. Décisions de conception

| Sujet | Choix | Motif |
| :--- | :--- | :--- |
| Chart | **`prometheus-community/kube-prometheus-stack` v92.1.0** (épinglé) | Standard moderne, un seul chart = Prometheus + Grafana + Alertmanager + node-exporter + kube-state-metrics + dashboards par défaut |
| Namespace / release | `monitoring` (release nommée `monitoring`) | Aligne le nom des services sur le distant (`monitoring-grafana`) |
| Secrets | Secret **en clair** `grafana-admin` (dev) via `admin.existingSecret` | Même pattern que le distant, sans SealedSecret |
| Persistance | **Désactivée** (ephemeral) | Démo locale ; évite des PVC inutiles |
| Composants K8s control-plane | `kubeEtcd`/`kubeControllerManager`/`kubeScheduler`/`kubeProxy` **désactivés** | Non scrapables sur Kind (sinon cibles « down » permanentes) |
| Accès | **port-forward** (ClusterIP) | Pas d'IngressController sur Kind |
| Loki / Promtail (logs) | **Hors périmètre v1** | Demandé : « prometheus et grafana » ; allège la stack |
| Dashboards projet (`grafana-dashboard-*.yaml`) | **Hors périmètre v1** | Liés à Loki/Infinity/Postgres → non fonctionnels sans plugins/datasources ; dashboards par défaut fournis à la place |

## 3. Livrables

```
crypto-bot-infra/
├── overlays/local-monitoring/
│   ├── kustomization.yaml     # namespace + secret (la partie Helm n'est pas kustomize)
│   ├── namespace.yaml         # namespace monitoring
│   ├── secret.yaml            # Secret grafana-admin (dev, clair)
│   └── values.yaml            # valeurs Helm kube-prometheus-stack (tunées Kind)
└── scripts/
    ├── local-monitoring-up.sh     # repo + secret + helm install + port-forwards
    └── local-monitoring-down.sh   # helm uninstall + suppression namespace
```

## 4. Ports d'accès (via port-forward)

| UI | Port local | Service |
| :--- | :--- | :--- |
| **Grafana** | **3000** | `monitoring/monitoring-grafana:80` |
| **Prometheus** | **9090** | `monitoring/monitoring-kube-prometheus-prometheus:9090` |
| **Alertmanager** | **9093** | `monitoring/monitoring-kube-prometheus-alertmanager:9093` |

Identifiants Grafana : `admin` / `admin` (secret `grafana-admin`, dev).

## 5. Étapes

1. Écrire `overlays/local-monitoring/` (namespace, secret, values, kustomization).
2. Écrire `scripts/local-monitoring-up.sh` / `local-monitoring-down.sh`.
3. Épingler la version du chart (`--version 92.1.0`), `helm upgrade --install --wait`.
4. Déployer, attendre, puis port-forwards Grafana/Prometheus/Alertmanager.
5. Valider (voir §6).

## 6. Validation

```
kustomize build overlays/local-monitoring           → OK
helm upgrade --install --wait                       → release deployed
kubectl -n monitoring get pods                      → tous Running (operator, prometheus, grafana, alertmanager, KSM, node-exporter)
curl http://localhost:3000/api/health               → 200 "database: ok"
curl http://localhost:9090/-/ready                  → 200
curl http://localhost:9090/api/v1/targets           → cibles up (kubelet, KSM, node-exporter, apiserver)
```

## 7. Risques / limites

- **RAM** : la stack ~1–1,5 GiB. Le nœud en a 47 GiB → OK.
- **Images** : ~10 images tirées depuis Docker Hub/quay au 1er `helm install` (réseau requis).
- **Alertmanager** : sans SMTP configuré, il tourne mais n'envoie rien (normal en local).
- **Dashboards projet** non chargés en v1 (cf. §2).

---

## 8. Statut d'implémentation

Implémenté et validé le 2026-10-07 sur `kind-crypto-bot`.

### Fichiers créés

| Fichier | Nature |
| :--- | :--- |
| `crypto-bot-infra/overlays/local-monitoring/{namespace,secret,values,kustomization}.yaml` | Overlay (ns + secret) + valeurs Helm |
| `crypto-bot-infra/scripts/local-monitoring-up.sh` | Repo + secret + `helm upgrade --install` + port-forwards |
| `crypto-bot-infra/scripts/local-monitoring-down.sh` | `helm uninstall` + suppression namespace |

### Validé — run réel

```
kustomize build overlays/local-monitoring     → OK (namespace + secret)
helm upgrade --install monitoring (v92.1.0)   → STATUS: deployed
kubectl -n monitoring get pods                → 6/6 Running
  alertmanager / grafana (3/3) / operator / kube-state-metrics / node-exporter / prometheus (2/2)
Grafana  http://localhost:3000/api/health      → 200 ; login admin/admin OK (/api/org 200)
Prometheus http://localhost:9090/-/ready       → 200
Alertmanager http://localhost:9093/-/ready     → 200
Prometheus targets                             → 14/14 up (apiserver, coredns, kubelet, KSM,
                                                  node-exporter, grafana, alertmanager, operator, prometheus)
Observabilité du namespace dev :
  kube_pod_status_phase{namespace="dev"} → 4 pods Running (backend, frontend, minio-0, postgres-0)
  container_memory_usage_bytes{namespace="dev"} → backend 122.8 MiB, frontend 52.7 MiB,
                                                 minio 99.7 MiB, postgres 79.9 MiB
```

### Ports

| UI | URL | Identifiants |
| :--- | :--- | :--- |
| Grafana | http://localhost:3000 | `admin` / `admin` |
| Prometheus | http://localhost:9090 (targets : `/targets`) | — |
| Alertmanager | http://localhost:9093 | — |

### Commandes

```bash
./scripts/local-monitoring-up.sh       # déploie + port-forwards
SKIP_FORWARD=1 ./scripts/local-monitoring-up.sh
./scripts/local-monitoring-down.sh     # --keep-ns pour conserver le namespace
```

### Restant (optionnel)

- Loki/Promtail (logs) et dashboards projet (Infinity/Postgres) : cf. §2, hors v1.
- Les CRD de kube-prometheus-stack restent après `local-monitoring-down.sh` (comportement
  Helm) ; `local-down.sh --purge` supprime tout le cluster.

---

## 9. Connexion au projet + dashboard

### État de connexion (avant §9)

| Source | Connecté au projet ? |
| :--- | :--- |
| Prometheus | **Oui, infra** : scrape kubelet/cAdvisor/KSM → pods de `dev` (statut, CPU, RAM, restarts) |
| Prometheus | **Non, métier** : l'app n'expose pas `/metrics` |
| Grafana | **Non** : aucune datasource Postgres → 0 donnée métier ; pas de Loki → 0 log |
| Dashboards projet | **Non chargés** localement (liés à Loki/Infinity/Postgres) |

### Ajouté en §9

1. **Datasource PostgreSQL « Postgres Dev »** (uid `crypto-bot-postgres`) provisionnée via
   `grafana.additionalDataSources`, credentials depuis le secret `grafana-postgres-creds`
   (variables `$DEV_POSTGRES_USER`/`$DEV_POSTGRES_PWD`), URL
   `postgres.dev.svc.cluster.local:5432` / base `crypto_bot_db`.
2. **Dashboard projet `Crypto-Bot - Projet (local Kind)`** (`uid crypto-bot-local`,
   ConfigMap `dashboard-crypto-bot-local`, chargé par le sidecar Grafana) :
   - *Applications (Prometheus)* : pods Running, conteneurs, restarts, cibles UP, nœuds Ready,
     mémoire/CPU par pod du namespace `dev` ;
   - *Données métier (PostgreSQL dev)* : utilisateurs, bot_templates, instances de bots, ordres,
     transactions + table « activité par table » ;
   - *Cluster Kind (Prometheus)* : CPU et mémoire du cluster.

### Validé

```
api/datasources                  → Postgres Dev (crypto-bot-postgres), Prometheus, Alertmanager
api/datasources/.../health       → status OK, "Database Connection OK"
api/search?query=Crypto-Bot      → "Crypto-Bot - Projet (local Kind)" chargé
Requête Postgres via Grafana     → users=0, bot_templates=2, orders=0
Requête Prometheus via Grafana   → pods Running (dev) = 4
```

> Note : les tables métier (`users`, `orders`, `transactions`…) sont **vides** en local
> (seul `bot_templates` a les 2 seeds) → le dashboard affiche 0, ce qui est normal.
> Les dashboards d'origine (`grafana-dashboard-infra.yaml`, `grafana-dashboard-crypto-bot.yaml`)
> ne sont toujours pas chargés : ils dépendent d'Infinity (sondes VM AWS) et de Loki (logs).


