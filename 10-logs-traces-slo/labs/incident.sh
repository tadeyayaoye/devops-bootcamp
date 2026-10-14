#!/usr/bin/env bash
# ⚠ NE LIS PAS CE SCRIPT AVANT D'AVOIR RÉSOLU L'INCIDENT (Lab 10.4 / module 11).
# Il déclenche au hasard une panne dans taskapi-dev et note la réponse dans ~/.bootcamp/.
set -euo pipefail

NS="${NS:-taskapi-dev}"          # NS=taskapi-prod bash incident.sh  → incident en prod
ENV_DIR="${NS#taskapi-}"
ROOT="$(git rev-parse --show-toplevel)"
GITOPS_DIR="${GITOPS_DIR:-$ROOT/../devops-bootcamp-gitops}"
LOG_DIR="$HOME/.bootcamp" && mkdir -p "$LOG_DIR"
STAMP=$(date +%Y%m%d-%H%M%S)
SCENARIO="${1:-$((RANDOM % 4 + 1))}"

chaos_all_pods() {   # chaos_all_pods '<json>'
  for p in $(kubectl -n $NS get pods -l app.kubernetes.io/name=taskapi -o name); do
    kubectl -n $NS exec "$p" -- python -c "
import urllib.request
r = urllib.request.Request('http://127.0.0.1:8000/chaos', data=b'$1', method='PUT', headers={'content-type': 'application/json'})
urllib.request.urlopen(r, timeout=3)" >/dev/null
  done
}

case "$SCENARIO" in
  1)
    chaos_all_pods '{"error_rate": 0.4, "latency_ms": 0}'
    ANSWER="Erreurs 5xx injectées (chaos error_rate=0.4) sur tous les pods. Mitigation : PUT /chaos error_rate=0 sur chaque pod, ou kubectl rollout restart (l'état du chaos est en mémoire)."
    ;;
  2)
    chaos_all_pods '{"error_rate": 0, "latency_ms": 900}'
    ANSWER="Latence injectée (chaos latency_ms=900). Visible : p95, SLO latence, traces (span du middleware). Mitigation : PUT /chaos latency_ms=0 ou rollout restart."
    ;;
  3)
    kubectl -n $NS apply -f - >/dev/null <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: zz-incident-egress
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: taskapi
  policyTypes: ["Egress"]
  egress: []
EOF
    kubectl -n $NS rollout restart deploy/taskapi >/dev/null
    ANSWER="NetworkPolicy 'zz-incident-egress' créée À LA MAIN (hors Git, donc ignorée par Argo CD) : tout l'egress des pods taskapi est bloqué (DNS + Postgres). Les nouveaux pods ne deviennent jamais Ready. Leçon : les requêtes qui n'atteignent pas l'appli n'apparaissent PAS dans ses métriques (il faut aussi superviser la Gateway / sonder de l'extérieur). Mitigation : kubectl -n $NS delete networkpolicy zz-incident-egress."
    ;;
  4)
    cd "$GITOPS_DIR" && git pull -q --rebase
    (cd "envs/$ENV_DIR" && kustomize edit set image ghcr.io/tadeyayaoye/taskapi:0000000)
    git commit -qam "chore($ENV_DIR): taskapi 0000000 (déploiement automatique)"
    git push -q
    ANSWER="Mauvais déploiement : tag d'image inexistant (0000000) poussé dans envs/$ENV_DIR. Nouveaux pods en ImagePullBackOff, anciens pods toujours en service grâce à maxUnavailable=0 (pas d'impact utilisateur !), application Argo CD Degraded/Progressing. Mitigation : git revert du commit dans le repo GitOps."
    ;;
  *) echo "scénario inconnu"; exit 1 ;;
esac

echo "[$STAMP] scénario $SCENARIO : $ANSWER" >> "$LOG_DIR/incidents.log"
echo "🚨 Incident déclenché à $(date +%H:%M:%S). Note l'heure. Bonne chance !"
echo "   (la réponse est dans ~/.bootcamp/incidents.log — ne la lis qu'après ton postmortem)"
