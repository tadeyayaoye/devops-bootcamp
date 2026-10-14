# Module 08 — GitOps avec Argo CD

> **Objectif** : comprendre le modèle GitOps (pull, réconciliation continue, Git comme source de vérité), maîtriser Argo CD (Applications, Projects, ApplicationSets, sync, santé, vagues), gérer les secrets dans Git, et mettre en place une vraie chaîne **CI → GitOps → cluster** avec promotion par Pull Request.
>
> **Durée** : cours ~1 h 45 · labs ~3 h 30 · quiz 30 min

---

## 1. Pourquoi GitOps

### Le déploiement « push » classique

```
CI (Jenkins/Actions) ──kubectl apply / helm upgrade──► cluster
```

Problèmes : la CI détient des **identifiants admin du cluster** (cible de choix pour un attaquant), elle doit **joindre** l'API du cluster (réseau), personne ne remarque si quelqu'un modifie le cluster à la main (**dérive**), et l'état réel n'est décrit nulle part de façon fiable.

### Le modèle GitOps (« pull »)

```
CI ──commit (nouveau tag)──► repo GitOps ◄──pull/watch── Argo CD (DANS le cluster) ──apply──► cluster
                              (état désiré)                    compare en continu
```

Les **4 principes OpenGitOps** :

1. **Déclaratif** : l'état désiré du système est décrit de façon déclarative.
2. **Versionné et immuable** : cet état est stocké dans un système qui garde l'historique complet (Git).
3. **Tiré automatiquement** : des agents récupèrent l'état désiré depuis la source.
4. **Réconcilié en continu** : les agents comparent en permanence l'état réel à l'état désiré et corrigent les écarts.

Bénéfices concrets :

| | |
|---|---|
| **Audit** | chaque changement de prod = un commit (qui, quand, pourquoi, revu par qui) |
| **Rollback** | `git revert` |
| **Sécurité** | aucun identifiant du cluster hors du cluster ; la CI n'a besoin que d'un droit d'écriture Git |
| **Dérive** | détectée et corrigée automatiquement (self-heal) |
| **Reprise après sinistre** | nouveau cluster + Argo CD + application racine = tout revient |
| **Self-service** | les équipes livrent par PR, sans accès direct au cluster |

C'est aussi la réponse à la limite vue au module 07 : la CI sur Internet ne peut pas joindre ton cluster local, mais ton cluster peut lire GitHub.

---

## 2. Organiser les repos

| Question | Recommandation |
|---|---|
| Code et manifests dans le même repo ? | **Non** : repo applicatif (code, Dockerfile, CI) + repo de configuration (GitOps). Évite les boucles CI, sépare les droits, historique de déploiement lisible |
| Une branche par environnement ? | **Non** (merges entre branches pénibles, divergences invisibles). **Un dossier par environnement** sur `main` (`envs/dev`, `envs/prod`) |
| Comment factoriser ? | Kustomize (base + overlays) ou Helm (chart + values par env) |
| Comment promouvoir ? | modifier le tag d'image du dossier de l'env cible, **par PR** pour la prod (revue = approbation de mise en prod) |

Notre structure :

```
devops-bootcamp-gitops/
├── bootstrap/root.yaml        ← appliqué UNE fois à la main
├── argocd/                    ← synchronisé par root : AppProjects, Applications, ApplicationSets
├── apps/{taskapi,postgres}/base/
├── envs/{dev,prod}/           ← overlays : namespace, tag d'image, hostnames, secret scellé
└── platform/                  ← valeurs Helm, règles, dashboards (modules 09-10)
```

---

## 3. Argo CD : architecture

```
                         ┌──────────────── namespace argocd ────────────────┐
  UI / CLI argocd ─────► │ argocd-server       API, UI, authentification     │
                         │ repo-server         clone Git, rend les manifests │◄── Git / repos Helm / OCI
                         │                     (kustomize build, helm template)│
                         │ application-controller  compare désiré ↔ réel,     │──► API Kubernetes
                         │                     calcule le diff, synchronise   │
                         │ applicationset-controller  génère des Applications│
                         │ redis               cache                         │
                         │ dex (SSO), notifications (optionnels)             │
                         └───────────────────────────────────────────────────┘
```

Le repo-server **rend** les manifests (Kustomize, Helm, YAML brut, Jsonnet, plugins), le contrôleur les compare aux objets live et applique le diff. Rafraîchissement : toutes les 3 min par défaut (`timeout.reconciliation`, 60 s chez nous), ou immédiatement via **webhook** Git.

---

## 4. Les objets d'Argo CD

### Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: { name: taskapi-dev, namespace: argocd }
spec:
  project: apps
  source:                                   # QUOI déployer
    repoURL: https://github.com/org/gitops.git
    targetRevision: main                    # branche, tag ou commit
    path: envs/dev                          # Kustomize détecté automatiquement
  destination:                              # OÙ
    server: https://kubernetes.default.svc
    namespace: taskapi-dev
  syncPolicy:                               # COMMENT
    automated: { prune: true, selfHeal: true }
    syncOptions: [CreateNamespace=true, ServerSideApply=true]
```

Pour un chart Helm : `chart: …` + `helm.valuesObject` ou **multi-sources** (le chart depuis son repo + un fichier de values depuis ton repo Git via `ref: values` et `$values/…`).

### Deux statuts à ne pas confondre

| Sync status | Health status |
|---|---|
| **Synced** / **OutOfSync** : le live correspond-il à Git ? | **Healthy**, **Progressing**, **Degraded**, **Missing**, **Suspended** : la ressource fonctionne-t-elle ? |
| calculé par diff | calculé par des règles par type (Deployment : réplicas disponibles ; PVC : Bound ; Ingress/Service LB : adresse…), extensibles en Lua |

Une app peut être **Synced mais Degraded** (le YAML est appliqué, mais le pod crashe) : c'est souvent là que se cache le problème.

### syncPolicy

| Option | Effet |
|---|---|
| `automated` | synchronise dès que Git change |
| `prune: true` | supprime du cluster ce qui a été retiré de Git (sinon : ressources orphelines) |
| `selfHeal: true` | annule les modifications manuelles (dérive) |
| `syncOptions` | `CreateNamespace`, `ServerSideApply` (gros CRD), `PruneLast`, `ApplyOutOfSyncOnly`, `RespectIgnoreDifferences`, `SkipDryRunOnMissingResource` (CRD pas encore installées) |
| `retry` | réessais avec backoff |
| `ignoreDifferences` | champs à ignorer (ex. `replicas` géré par un HPA, champs mutés par un webhook) |

### Vagues et hooks

- **Sync waves** (`argocd.argoproj.io/sync-wave: "-1"`) : ordre d'application ; Argo attend que la vague soit *Healthy* avant la suivante. Ex. : AppProjects (-10) → contrôleur de secrets (-5) → base de données (0) → application (1).
- **Hooks** (`argocd.argoproj.io/hook: PreSync | Sync | PostSync | SyncFail`) : Jobs exécutés à un moment du sync (migrations de schéma en PreSync, tests de fumée en PostSync, notification en SyncFail).

### AppProject

Garde-fous multi-équipes : dépôts sources autorisés, clusters/namespaces de destination autorisés, types de ressources autorisés (une équipe applicative ne doit pas pouvoir créer de ClusterRole), rôles RBAC, fenêtres de synchronisation (*sync windows* : pas de déploiement le vendredi soir…).

### App of apps et ApplicationSet

- **App of apps** : une Application « racine » pointe vers un dossier contenant… d'autres Applications. Un seul `kubectl apply` amorce tout le cluster (*bootstrap*).
- **ApplicationSet** : un **générateur** + un **template** → N Applications.

| Générateur | Usage |
|---|---|
| `list` | liste explicite d'environnements |
| `git` (directories / files) | une app par dossier `envs/*` ✅ (notre cas) |
| `clusters` | une app par cluster enregistré (multi-cluster) |
| `matrix` / `merge` | combinaisons (apps × clusters) |
| `pullRequest` | **environnement éphémère par PR** |
| `scmProvider` | une app par repo d'une organisation |

---

## 5. Secrets en GitOps

Git est la source de vérité… mais un Secret en clair dans Git est inacceptable (même dans un repo privé). Solutions :

| Solution | Principe | + / − |
|---|---|---|
| **Sealed Secrets** (notre choix) | `kubeseal` chiffre avec la clé **publique** d'un contrôleur du cluster ; on commite le `SealedSecret` ; seul le contrôleur peut déchiffrer et crée le `Secret` | simple, autonome ; lié au cluster (sauvegarder la clé privée du contrôleur !), rotation manuelle |
| **SOPS** (+ age/KMS) | fichiers chiffrés dans Git, déchiffrés au rendu (plugin Argo CD, KSOPS, Flux natif) | souple, multi-cloud ; gestion des clés |
| **External Secrets Operator** | Git contient une **référence** (`ExternalSecret`) ; l'opérateur va chercher la valeur dans Vault / AWS Secrets Manager / Azure Key Vault / GCP | ✅ standard en entreprise : rotation centralisée, audit ; nécessite un coffre |
| Vault Agent / CSI driver | injection au runtime dans le pod | aucune trace dans Kubernetes Secrets ; plus complexe |

**Portée Sealed Secrets** : par défaut *strict* — un secret scellé pour `taskapi-db` dans `taskapi-dev` ne peut être déchiffré que sous **ce nom, dans ce namespace** (impossible de le copier ailleurs).

---

## 6. Le flux complet du bootcamp

```
dev push (app/) ──► Jenkins : tests, Sonar, Trivy, build ──► GHCR : taskapi:1a2b3c4
                                   │
                                   └─► commit "chore(dev): taskapi 1a2b3c4" dans envs/dev   (automatique)
                                                    │
                          Argo CD voit le commit ◄──┘  → sync taskapi-dev → rolling update
                                                    
Promotion : PR "envs/prod → 1a2b3c4" ──revue──► merge ──► Argo CD sync taskapi-prod
Rollback  : git revert de la PR (ou du commit dev)  ──► Argo CD resynchronise l'ancienne version
```

Notes :
- **La même image** (même digest) passe de dev à prod : aucun rebuild.
- `argocd app rollback` existe mais **désactive l'auto-sync** et crée une dérive avec Git : en GitOps on préfère **`git revert`**.
- Pour des stratégies avancées (canary progressif piloté par les métriques, blue/green), **Argo Rollouts** remplace le Deployment par un `Rollout` ; Flagger fait de même avec Flux.
- **Argo CD Image Updater** (ou Renovate) peut mettre à jour le tag dans Git automatiquement à la place de la CI.

---

## 7. Argo CD vs Flux

| | Argo CD | Flux |
|---|---|---|
| UI | ✅ riche (graphe des ressources, diff, logs) | non native (Weave GitOps, Capacitor) |
| Modèle | Applications centralisées, multi-cluster depuis une instance | contrôleurs par cluster (Kustomization, HelmRelease) |
| Secrets | plugins | SOPS natif |
| Multi-tenant | AppProjects + RBAC | via namespaces et RBAC K8s |
| Adoption | très large, CNCF graduated | CNCF graduated, intégré dans Azure Arc/GitLab |

Les deux sont des choix solides ; Argo CD est plus fréquent dans les offres d'emploi.

---

## 8. Opérer Argo CD

```bash
argocd login argocd.localhost --plaintext --grpc-web       # ou: argocd login --core
argocd app list
argocd app get taskapi-dev                                 # statut, ressources, dernier sync
argocd app diff taskapi-dev                                # diff Git ↔ live
argocd app sync taskapi-dev [--prune]                      # sync manuel
argocd app history taskapi-dev
argocd app logs taskapi-dev --kind Deployment --name taskapi
argocd app set taskapi-dev --sync-policy none              # suspendre l'auto-sync (incident)
argocd admin initial-password -n argocd
```

- **Sécurité** : changer/supprimer le compte `admin` initial, SSO (Dex/OIDC), RBAC par projet, accès UI uniquement en interne.
- **Haute disponibilité** : réplicas du repo-server et du contrôleur (sharding par cluster), Redis HA.
- **Notifications** (Slack, Teams, mail) sur sync réussi/échoué, app dégradée.

---

## Pièges classiques

- `kubectl edit` en prod sur une app en self-heal → modification annulée en 1 min (c'est voulu !). Il faut passer par Git.
- `prune: false` → des ressources supprimées de Git restent en vie (orphelines).
- HPA + `replicas` dans Git → oscillations : `ignoreDifferences` + pas de `replicas` dans le manifeste.
- CRD trop grosses → `ServerSideApply=true`. Ressources qui dépendent de CRD pas encore installées → vagues + `SkipDryRunOnMissingResource=true`.
- Perdre la clé privée de Sealed Secrets (cluster recréé) → tous les secrets scellés sont illisibles : la sauvegarder (`kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml`) dans un coffre, ou re-sceller.
- Changer le mot de passe dans le Secret ne change pas celui déjà enregistré dans une base Postgres initialisée.
- Images `:latest` / tags mobiles → Argo ne voit aucun changement dans Git, rien ne se redéploie.

---

## Pour aller plus loin

- [OpenGitOps — principes](https://opengitops.dev/)
- [Argo CD — documentation](https://argo-cd.readthedocs.io/) (Best practices, Sync options, ApplicationSet)
- [Codefresh — GitOps environment promotion](https://codefresh.io/blog/how-to-model-your-gitops-environments-and-promote-releases-between-them/)
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) · [External Secrets Operator](https://external-secrets.io/)
