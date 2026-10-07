# Remédiation — Étude de faisabilité Kind

> **Complément à [DEPLOIEMENT_KIND_INFRA.md](./DEPLOIEMENT_KIND_INFRA.md).**
> Ce document liste les corrections et les trous à combler dans l'analyse Gemini
> **avant** de passer à l'implémentation. Il ne remplace pas l'analyse, il la corrige.

| Métadonnée | Valeur |
| :--- | :--- |
| Date de vérification | 2026-10-07 |
| Poste | macOS, Docker 28.2.2, `kind` (contexte `kind-kind`, Kubernetes v1.36.1) |
| Outils | kustomize v5.8.1, kubectl, kind, k3d, minikube, helm v4.2.0, ansible |
| Cluster local courant | `kind-kind` (StorageClass par défaut `standard`, provisioner `rancher.io/local-path`) |
| Portée | Le namespace `dev` sur un cluster Kind (les 4 services socles) |

---

## 0. Synthèse — ce qu'il faut corriger avant d'implémenter

| # | Point | Statut Gemini | Réalité vérifiée | Action |
| :-- | :--- | :--- | :--- | :--- |
| 1 | Secret K8s standard | Liste de clés proposée | **Incomplète** → backend en `CrashLoopBackOff` | Ajouter 3 clés obligatoires (§1) |
| 2 | Image MinIO | `elestio/minio:latest` | Mirror communautaire **qui marche**, mais le repo officiel est cassé partout | Décider la source et l'épingler (§2) |
| 3 | Stockage distant | « CSI Proxmox/Talos » | Talos = OS ; stockage = `local-path-provisioner` (idem Kind) | Reformuler (§3.1) |
| 4 | StorageClass Kind | « `local-path` » | Sur Kind le SC par défaut s'appelle **`standard`** | Décision : ne pas pinner `storageClassName` (§3.2) |
| 5 | `overlays/local` | Présenté comme prêt | **N'existe pas** | Le créer (§5) |
| 6 | Bootstrap bucket | « manquant » (dit par l'analyse ?) | Non bloquant : le backend auto-crée le bucket | Job optionnel (§3.3) |
| 7 | Version `kind-control-plane v1.36.1` | Confondu avec la version de Kind | C'est la version **Kubernetes** du nœud | Reformuler (§3.4) |

---

## 1. BLOQUANT A — Le Secret proposé est incomplet

### Preuve

Le backend n'a **aucune valeur par défaut** pour ces trois variables (pydantic
`BaseSettings`, `backend/src/shared/config/settings.py`) :

```
settings.py:36  JWT_SIGNING_KEY: SecretStr          # pas de défaut
settings.py:50  CORS_ORIGINS: Annotated[list[str], NoDecode]   # pas de défaut
settings.py:59  ALLOWED_HOSTS: Annotated[list[str], NoDecode]  # pas de défaut
```

Or le pod consomme le secret en bloc :

```yaml
# crypto-bot-infra/base/backend/deployment.yaml:60
envFrom:
  - secretRef:
      name: crypto-bot-secrets
```

Si une de ces 3 clés manque → `pydantic.ValidationError` au démarrage →
`CrashLoopBackOff`. Le secret proposé par Gemini
(`DEPLOIEMENT_KIND_INFRA.md:125-134`) ajoute `JWT_SIGNING_KEY` mais **omet
`CORS_ORIGINS` et `ALLOWED_HOSTS`** → backend KO.

### Trous additionnels constatés

- L'image backend ne contient **aucun `.env`** (`backend/Dockerfile` : `COPY backend/ .`
  avec `backend/.env` inexistant) : aucune valeur ne peut venir d'ailleurs.
- Le `SealedSecret` de référence `overlays/dev/secrets.yaml` **ne contient ni
  `JWT_SIGNING_KEY`, ni `CORS_ORIGINS`, ni `ALLOWED_HOSTS`** (il n'a que
  `EXCHANGE_ENC_KEY, MINIO_ACCESS_KEY, MINIO_SECRET_KEY, MONGODB_PWD, MONGODB_USER,
  POSTGRES_PWD, POSTGRES_USER, SECRET_KEY`). **Le sealed secret commité est donc
  désynchronisé de l'application** : le déploiement distant `dev`/`staging`/`production`
  planterait aussi. À vérifier côté infra de soutenance (le secret réellement déployé
  sur le cluster est peut-être plus à jour que celui du repo).
- Gemini a retiré `MONGODB_USER` / `MONGODB_PWD`, qui sont bien présents dans le
  sealed secret. Ils ne sont pas requis par `settings.py` du backend, donc non bloquants
  pour les 4 services socles, mais à conserver pour la parité.

### Secret minimal à créer pour `overlays/local`

| Clé | Requis par | Valeur locale suggérée |
| :--- | :--- | :--- |
| `POSTGRES_USER` | postgres, backend | `postgres` |
| `POSTGRES_PWD` | postgres, backend | `postgres` |
| `MINIO_ACCESS_KEY` | minio, backend | `minioadmin` |
| `MINIO_SECRET_KEY` | minio, backend | `minioadmin` |
| `JWT_SIGNING_KEY` | backend (**obligatoire**) | clé de dev générée |
| `CORS_ORIGINS` | backend (**obligatoire**) | `http://localhost:8511,http://crypto-bot-frontend:8501` |
| `ALLOWED_HOSTS` | backend (**obligatoire**) | `localhost,127.0.0.1,crypto-bot-backend` |
| `SECRET_KEY` | (divers, optionnel) | valeur de dev |
| `EXCHANGE_ENC_KEY` | jobs d'ingestion (optionnel ici) | `AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=` |

> `ALLOWED_HOSTS` **doit** contenir `crypto-bot-backend` : la liveness probe du backend
> envoie `Host: crypto-bot-backend` (`base/backend/deployment.yaml:47-49`) ; sinon la
> probe renvoie 400 → `CrashLoopBackOff`.

---

## 2. BLOQUANT B — L'image MinIO n'est plus disponible (cause racine réelle)

### Contexte

Le 25/04/2026 le projet MinIO a été **archivé** (dépôt GitHub en lecture seule). Les
images conteneur ne sont plus distribuées publiquement. C'est la cause du crash initial
de `make dev-up` sur `crypto-bot-app` — **ce n'était pas** le problème `credsStore`
décrit dans `orchestration/docs/04-troubleshooting.md` (Problème 6).

### Preuves mesurées le 2026-10-07

| Référence | Méthode | Résultat |
| :--- | :--- | :--- |
| `docker.io/minio/minio:latest` | token Hub + manifest | **HTTP 401** (`pull access denied … repository does not exist`) |
| `docker.io/minio/mc:latest` | idem | **HTTP 401** |
| `quay.io/minio/minio:latest` et `:RELEASE.2025-09-07T16-13-09Z` | token quay anonyme | **HTTP 401 UNAUTHORIZED** |
| `quay.io/minio/mc` | idem | **HTTP 401 UNAUTHORIZED** |
| `dl.min.io/server/minio/release/linux-amd64/minio` | curl | **HTTP 410 Gone** |
| `quay.io/prometheus/prometheus:latest` *(contrôle)* | token quay anonyme | **HTTP 200** ✅ |

**Conclusion du contrôle** : l'accès anonyme à quay.io fonctionne pour les repos publics
(prometheus → 200). Donc `minio/minio` et `minio/mc` sur quay sont **réellement
restreints/supprimés**, et pas un simple problème de credentials du poste.

### Conséquence directe sur `crypto-bot-infra`

`base/minio/statefulset.yaml` épingle pourtant :

```yaml
image: quay.io/minio/minio:RELEASE.2025-09-07T16-13-09Z
```

Ce manifeste **hérité par `dev`, `staging` et `production`** (aucun overlay ne patche
l'image MinIO) est donc **actuellement indéployable** sans credentials MinIO. Le problème
n'est pas propre à Kind : il touche aussi le cluster distant.

### Options de remédiation (décision requise)

| Option | Détail | Avantages | Risques |
| :--- | :--- | :--- | :--- |
| **A. Credentials MinIO** | Obtenir un accès (compte MinIO/AIStor) sur `quay.io/minio/minio`, créer un `imagePullSecret` | Image **officielle**, aucune dérive | Dépend d'un accès qui n'est plus garanti publiquement |
| **B. Mirror communautaire** | Utiliser `elestio/minio`, `pgsty/minio` ou `chainguard/minio` **épinglé par digest** | Marche immédiatement (vérifié HTTP 200) | **Chaîne d'approvisionnement** : tiers, à documenter pour la soutenance |
| **C. Build local** | Reconstruire depuis des sources/binaires tiers | Contrôle total | `dl.min.io` = 410 ; sources officielles coupées → peu viable |

Mirrors vérifiés (2026-10-07, `HTTP 200`) :

- `docker.io/elestio/minio:latest` → digest `sha256:25348a257f1ece1b192f25f6cd9854618fa86422ac87b494b5d4e629c556d4bd`
- `docker.io/pgsty/minio:latest`
- `docker.io/chainguard/minio:latest`
- `docker.io/pgsty/mc:latest` (client `mc` pour un éventuel Job bucket)

> **À valider par un vrai `docker pull` + `docker run --rm <image> --version`** avant de
> câbler, car `docker manifest inspect` du poste renvoie des faux négatifs sur quay
> (cf. §6). Si `elestio/minio` est retenu, vérifier qu'il contient bien `curl` (healthcheck
> `docker-compose`) et que l'entrypoint `server /data --console-address ":9001"` fonctionne.

### Impact sur `crypto-bot-app` (chemin Docker Compose)

Correctif minimal d'une ligne dans `crypto-bot-app/versions.env` :

```diff
- MINIO_IMAGE=minio/minio
- MINIO_MC_IMAGE=minio/mc
+ MINIO_IMAGE=<mirror retenu>:<tag épinglé>
+ MINIO_MC_IMAGE=<mirror mc retenu>:<tag épinglé>
```

---

## 3. Corrections factuelles au document Gemini

### 3.1 Stockage du cluster distant — ligne 89

Affirmé : « CSI de virtualisation Proxmox/Talos ».
Réel : **Talos est l'OS** des VM (`docs/INSTALL.md:177`), le stockage du cluster distant
est **`local-path-provisioner`** (`docs/INSTALL.md:302-313`), **exactement le même
provisioner que Kind**. Il n'y a donc **aucune adaptation de stockage** à faire — la
ligne du tableau laisse croire le contraire.

### 3.2 Nom de la StorageClass sur Kind — ligne 89

Affirmé : Kind intègre « `local-path-storage` ».
Réel : le provisioner est bien `rancher.io/local-path`, mais sur Kind la StorageClass
par défaut se nomme **`standard`** (vérifié sur `kind-kind`) :

```
NAME                 PROVISIONER             RECLAIMPOLICY   ...
standard (default)   rancher.io/local-path   Delete          ...
```

Comme les PVC de `base/postgres` et `base/minio` ne pinnent **pas** de `storageClassName`,
ils se lient au SC par défaut : **rien à faire**, mais ne pas pinner `local-path` (nom
qui n'existe pas sur Kind).

### 3.3 Bootstrap du bucket — préciser

`docker-compose.yml` lance un service one-shot `createbuckets` (`mc mb crypto-bot-data`)
sans équivalent K8s. **Non bloquant** : le client applicatif auto-crée le bucket
(`crypto-bot-app/utils/connectors/minio.py:46-53` → `_ensure_bucket`). Un Job `mc mb`
reste utile pour la parité/robustesse, mais n'est pas requis pour que le backend démarre.

### 3.4 Version de Kind — ligne 3

« `kind-control-plane v1.36.1` » est la version **Kubernetes** du nœud
(`kubectl version` → `Server Version: v1.36.1`), pas la version de l'outil `kind`.

### 3.5 Ce qui est exact (à conserver tel quel)

- Mapping des ports `dev` (`8019/8511/5442/9020/9021`) — conforme à `scripts/port-forward.sh`.
- Tailles PVC : PostgreSQL `5Gi`, MinIO `10Gi`.
- Airflow et MLflow **absent** de `crypto-bot-infra`.
- `SealedSecret` → `Secret` standard, `kind load docker-image`, `port-forward` au lieu
  d'Ingress : bonne approche.
- Noms d'images locales Compose `crypto-bot-app-crypto-bot-backend:latest` /
  `crypto-bot-app-crypto-bot-frontend:latest` (préfixe = nom du dossier projet Compose).
- `imagePullPolicy: Always` en base → bien à surcharger en `IfNotPresent` en local
  (`base/backend/deployment.yaml:28`, `base/frontend/deployment.yaml:29`).

---

## 4. Compléments Kind non couverts par l'analyse

1. **`imagePullSecrets: gitlab-registry`** présent en base
   (`base/backend/deployment.yaml:23-24`, `base/frontend/deployment.yaml:23-24`) : l'overlay
   local doit **retirer cette dépendance**, sinon `ImagePullBackOff` sur un registry privé.
   (Bien identifié par Gemini, mais l'action concrète — patch `kustomize` de suppression —
   n'était pas donnée.)
2. **Namespace `dev`** : créé en impératif dans le guide Gemini, alors qu'il existe un
   manifeste `overlays/dev/namespace.yaml`. En local, garder `namespace: dev`.
3. **`kind load docker-image`** exige que le cluster soit déjà créé (`kind create cluster`)
   et que le **contexte Kubernetes** soit le bon (`kind-kind` ici).
4. **Aucun Ingress Controller local** : le choix `port-forward` est correct ; ne pas
   appliquer `overlays/dev/ingress.yaml` (classe `nginx` inexistante sur Kind).
5. **Contrôleurs absents localement** : ni `sealed-secrets`, ni ArgoCD (vérifié :
   `kubectl get crd | grep sealed` → rien). Wrapper Kustomize local = **pas de SealedSecret**.

---

## 5. Plan d'implémentation (à exécuter après décision sur §2)

```
crypto-bot-infra/overlays/local/
├── kustomization.yaml     # hérite de ../../base + patches locaux
├── namespace.yaml         # namespace: dev (ou local)
├── secret.yaml            # Secret clair (clés du §1)
├── images-patch.yaml      # retire imagePullSecrets, force IfNotPresent, images locales
└── minio-patch.yaml       # remplace l'image MinIO par la source retenue
```

Contenu attendu de l'overlay (spécification, **non implémenté** à ce stade) :

- `kustomization.yaml` : `resources: [../../base, namespace.yaml, secret.yaml]`,
  `images:` pour retaguer backend/frontend, et patches ciblés.
- Suppression de `imagePullSecrets` : patch stratégique
  (`spec.template.spec.imagePullSecrets: null`) sur les 2 Deployments.
- `imagePullPolicy: IfNotPresent` sur backend et frontend.
- `minio-patch.yaml` : `op: replace` sur l'image du StatefulSet `minio` (source §2).
- Script d'amorçage `scripts/local-up.sh` (à créer) :
  1. `kind create cluster` (si absent) ;
  2. `docker compose build` des images applicatives puis `docker tag`/`kind load` ;
  3. `kubectl apply -k overlays/local` ;
  4. `kubectl wait --for=condition=Ready pod ...` + `port-forward` (ports `dev`).

Correctif `crypto-bot-app/versions.env` (chemin Compose) : cf. §2.

---

## 6. Procédures de vérification

```bash
# 1. Disponibilité réelle d'une image MinIO candidate (le seul test fiable) :
docker pull <mirror>/minio:<tag> && docker image inspect <mirror>/minio:<tag>

# 2. Après déploiement :
kubectl get pods,pvc -n dev
kubectl logs -n dev deploy/crypto-bot-backend | head -40   # doit passer la validation pydantic
kubectl port-forward -n dev svc/crypto-bot-backend 8019:8009 &
curl -s http://localhost:8019/health
```

> Piège : `docker manifest inspect quay.io/...` renvoie **« no such manifest » même pour
> des images valides** sur ce poste (ex. cert-manager), à cause de l'authentification
> Docker Desktop. Ne pas conclure sur cette base ; utiliser un `docker pull` réel ou le
> flux `curl` + token du registre (cf. les preuves du §2).

---

## 7. Décisions à prendre avant codage

1. **Source de l'image MinIO** : option A (credentials officiels), B (mirror épinglé par
   digest) ou C (build) ? — conditionne `base/minio/statefulset.yaml` **et**
   `crypto-bot-app/versions.env`.
2. **Cible** : déployer sur Kind uniquement, ou corriger d'abord le chemin Compose
   (1 ligne) ? Kind n'a de sens que pour la **démonstration K8s** de la soutenance.
3. **Secret local** : confirmer les valeurs de `CORS_ORIGINS` / `ALLOWED_HOSTS` (cf. §1)
   et le caractère jetable de ces valeurs.
4. **Bucket** : Job `mc mb` de parité, ou s'appuyer sur l'auto-création du backend (§3.3) ?
5. **Repo `crypto-bot-infra` distant** : confirmer que le sealed secret du cluster réel
   contient bien les 3 clés obligatoires (§1) — sinon la prod est déjà cassée.

---

## 8. Statut d'implémentation

Implémenté le 2026-10-07.

### Décisions prises

| Décision (§7) | Choix retenu |
| :--- | :--- |
| Source MinIO | **`pgsty/minio` + `pgsty/mc`**, épinglés par tag `RELEASE` **et** digest |
| Périmètre | **Les deux** : `crypto-bot-infra` (Kind) **et** `crypto-bot-app` (Compose) |
| Job bucket | **Oui** (Job `minio-createbuckets`, parité avec le service Compose) |

Vérifications images pgsty (2026-10-07) : les deux images sont des **remplacements
directs** de l'officiel.
- `pgsty/minio` : `ENTRYPOINT=/usr/bin/docker-entrypoint.sh`, contient `curl` **et** `mc` ;
  l'invocation du StatefulSet (`docker-entrypoint.sh server /data --console-address :9001`)
  démarre bien le serveur (testé).
- `pgsty/mc` : `ENTRYPOINT=/usr/bin/mc`, `/bin/sh` présent (le service Compose `createbuckets`
  en `/bin/sh -c` reste fonctionnel — ce que `chainguard/minio-client` distroless cassait).

Digests épinglés :
- `pgsty/minio@sha256:b6bfe7239bfc83fb90d31612d9704d86039dd714f7904b3f1ad68f211e602372` (tag `RELEASE.2026-08-04T00-00-00Z`)
- `pgsty/mc@sha256:cfc83108c3abb371f8fb84d99c1fdc88f8c237e022409b0081fb7c0a3be634dd` (tag `RELEASE.2026-09-16T00-00-00Z`)

### Fichiers créés / modifiés

| Fichier | Nature |
| :--- | :--- |
| `crypto-bot-infra/overlays/local/kustomization.yaml` | **créé** — hérite de `base`, `images:` (backend/frontend locaux + MinIO pgsty), patches |
| `crypto-bot-infra/overlays/local/namespace.yaml` | **créé** — namespace `dev` |
| `crypto-bot-infra/overlays/local/secret.yaml` | **créé** — Secret clair, clés obligatoires incluses (§1) |
| `crypto-bot-infra/overlays/local/bucket-job.yaml` | **créé** — Job `mc mb` (image pgsty/mc épinglée) |
| `crypto-bot-infra/scripts/local-up.sh` | **créé** — cluster Kind + build + `kind load` + apply + rollout + port-forward |
| `crypto-bot-infra/scripts/local-down.sh` | **créé** — suppression namespace (option `--purge` du cluster) |
| `crypto-bot-infra/scripts/port-forward.sh` | **modifié** — contexte kubectl paramétrable en 2ᵉ argument (backward-compatible) |
| `crypto-bot-app/versions.env` | **modifié** — `MINIO_IMAGE`/`MINIO_MC_IMAGE` → pgsty épinglés |

### Écarts par rapport à la spécification §5

- Le retrait `imagePullSecrets` + `imagePullPolicy: IfNotPresent` et le changement d'image
  MinIO sont faits dans un **seul `kustomization.yaml`** (transform `images:` + patches
  JSON6902), au lieu des fichiers séparés `images-patch.yaml` / `minio-patch.yaml` :
  plus court, et le transform `images:` permet d'épingler le **digest**.
- Namespace retenu : **`dev`** (parité avec `scripts/port-forward.sh`).
- `versions.env` avait été basculé entre-temps sur `elestio/minio:latest` +
  `chainguard/minio-client:latest-dev` : **remplacé** (distroless → `createbuckets` cassé ;
  `:latest` → violation de la convention d'épinglage du repo).

### Corrections découvertes à l'exécution (2026-10-07)

1. **`versions.env` n'est pas du shell valide** — `AIRFLOW_SQLALCHEMY_SPEC=>=1.4.28,<2.0`
   provoque une redirection `<2.0` si on `source` le fichier (`make` le tolère via
   `include`, pas le shell). `local-up.sh` n'`exporte` plus le fichier : il extrait les
   clés utiles avec un parseur `sed` et passe `--env-file versions.env --env-file .env`
   à `docker compose`.
2. **Course au démarrage du backend** — sans attente de PostgreSQL, le backend démarre
   avant la base et bascule **définitivement** sur le fallback SQLite
   (`USE_SQLITE_FALLBACK=true`) : `📊 Database: SQLITE` dans les logs. L'overlay `local`
   ajoute un `initContainer` `wait-for-postgres` (`pg_isready` en boucle) → un déploiement
   à froid utilise bien `📊 Database: POSTGRESQL`.

### Validé — run réel de bout en bout (`./scripts/local-up.sh`, cluster `kind-crypto-bot`)

```
Cluster Kind créé                 → kind-crypto-bot (Kubernetes v1.36.1)
Build backend/frontend            → OK (cache)
kind load (5 images)              → backend, frontend, pgsty/minio, pgsty/mc, postgres
kubectl apply -k overlays/local   → 11 ressources
Pods                              → 5/5 Running/Completed
PVC                               → postgres-data 5Gi Bound, minio-data 10Gi Bound (SC standard)
Rollout à froid                   → 📊 Database: POSTGRESQL (initContainer OK)
Job minio-createbuckets           → Completed (bucket crypto-bot-data créé)
PostgreSQL                        → 21 tables + 2 bot_templates (seed)
MinIO                             → bucket crypto-bot-data présent (mc + disque)
```

Smoke tests HTTP (via port-forward) :

```
backend  /health             200  {"status":"healthy",...}
backend  /api/v1/docs        200
frontend /                   200
frontend /_stcore/health     200
minio    /minio/health/live  200
```

Chemin Compose (crypto-bot-app) :

```
make dev-config                                   → OK, image pgsty/minio résolue
docker compose --profile tools up createbuckets   → bucket créé, exit 0 (pgsty/mc)
```

### Restant à faire (manuel)

1. `make dev-up` complet (stack Compose entier : Airflow + MLflow + ml-api) **non exécuté**
   ici : hors périmètre de la remédiation et lourd. Le point bloquant initial (image MinIO)
   est levé et vérifié isolément ; lancer `make dev-up` si l'on veut la stack complète.
2. Traiter le point §7.5 : vérifier le **sealed secret du cluster distant** (3 clés
   obligatoires) — sinon la prod est cassée indépendamment du local.
3. `kubeconform`/`shellcheck` absents du poste : installer si l'on veut compléter la CI locale.


```
