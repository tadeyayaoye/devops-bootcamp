# Argo CD & GitOps — fiche mémo

```bash
argocd login <host> --plaintext [--grpc-web]     argocd login --core     # sans serveur, via kubeconfig
argocd admin initial-password -n argocd          argocd account update-password
argocd app list                                  argocd app get <app> [--refresh | --hard-refresh]
argocd app diff <app>                            argocd app sync <app> [--prune] [--resource kind:name]
argocd app wait <app> --sync --health --timeout 300
argocd app history <app>                         argocd app rollback <app> <id>   # ⚠ coupe l'auto-sync : préférer git revert
argocd app set <app> --sync-policy none|automated [--self-heal] [--auto-prune]
argocd app logs <app> --kind Deployment --name x
argocd app delete <app> [--cascade=false]
argocd proj list / get / windows list            argocd repo list           argocd cluster list
kubeseal --format yaml < secret.yaml > sealed.yaml   # contrôleur : kube-system/sealed-secrets-controller
```

Annotations utiles :
- `argocd.argoproj.io/sync-wave: "-1"` — ordre d'application
- `argocd.argoproj.io/hook: PreSync | Sync | PostSync | SyncFail` + `argocd.argoproj.io/hook-delete-policy: BeforeHookCreation`
- `argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true` / `Prune=false` / `ServerSideApply=true`
- `argocd.argoproj.io/compare-options: IgnoreExtraneous`

`syncPolicy` : `automated: { prune, selfHeal }` · `syncOptions: [CreateNamespace=true, ServerSideApply=true, PruneLast=true, RespectIgnoreDifferences=true]` · `retry`.
`ignoreDifferences: [{ group: apps, kind: Deployment, jsonPointers: [/spec/replicas] }]`.

Statuts : **Sync** = Git ↔ live (Synced/OutOfSync) · **Health** = fonctionne (Healthy/Progressing/Degraded/Missing/Suspended).

Flux GitOps : CI → image:sha → commit tag dans `envs/dev` → Argo sync → PR `envs/prod` → merge → sync prod → rollback = `git revert`.
