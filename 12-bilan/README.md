# Module 12 — Bilan (dimanche 26 octobre)

> ⏱ 4-5 h · Objectif : transformer 12 jours de pratique en connaissances **solides et restituables**, et savoir précisément ce qui reste flou.

| Bloc | Durée | Fichier |
|---|---|---|
| 1. Auto-évaluation par techno, avec critères observables | 45 min | [AUTO-EVALUATION.md](AUTO-EVALUATION.md) |
| 2. Exercices « à blanc » : réécrire de mémoire, sans doc | 1 h 30 | [EXERCICES-A-BLANC.md](EXERCICES-A-BLANC.md) |
| 3. Questions transverses (scénarios, conception) à voix haute | 1 h | [QUESTIONS-TRANSVERSES.md](QUESTIONS-TRANSVERSES.md) |
| 4. Relecture express des 12 quiz : uniquement les questions ratées | 45 min | `*/QUIZ.md` |
| 5. Plan de la suite | 15 min | [SUITE.md](SUITE.md) |
| 6. Nettoyage du poste | 15 min | ci-dessous |

## Nettoyage (quand tu as fini)

```bash
make sealed-key-backup                                   # si tu veux pouvoir tout remonter plus tard
make down                                                # cluster + CI
docker compose -f 05-ansible/lab/compose.yaml down
docker system df && docker system prune -a --volumes     # ⚠ supprime images et volumes inutilisés (dont SonarQube)
```

Tes deux repos GitHub restent : c'est ton **portfolio**. Un README racine soigné + le pitch du module 11 = un excellent support d'entretien.

Pour libérer l'espace disque de WSL après le nettoyage : `wsl --shutdown` dans PowerShell (le disque virtuel se compacte grâce à `sparseVhd=true`).
