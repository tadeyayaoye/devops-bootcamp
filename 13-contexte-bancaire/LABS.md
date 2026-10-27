# Module 13 — Exercices : les documents de la production

> ⏱ ~1 h 30 · Pas d'outil à installer : on écrit, comme en mission. Range tes documents dans `13-contexte-bancaire/livrables/`.

---

## Exercice 13.1 — Une RFC pour la mise en production de taskapi (≈ 30 min)

Tu veux mettre en production la fonctionnalité `/api/tasks/stats` (module 11). Rédige `livrables/RFC-taskapi-stats.md` avec :

1. **Identification** : titre, demandeur, application, environnement, date et fenêtre d'intervention souhaitées.
2. **Description** du changement et **justification** métier.
3. **Type** de changement (standard / normal / urgent) et **pourquoi**.
4. **Analyse d'impact et de risque** : services touchés, utilisateurs, dépendances (base, batch ?), niveau de risque.
5. **Plan de déploiement** pas à pas (en t'appuyant sur ta vraie chaîne : PR GitOps, Argo CD…).
6. **Plan de tests** (avant et après MEP : quoi vérifier, comment, qui).
7. **Plan de retour arrière** : déclencheur (« si … alors on revient en arrière »), procédure, durée estimée.
8. **Communication** : qui prévenir avant / pendant / après.

Question à te poser : avec ta chaîne actuelle (tests, scans, GitOps, rollback par revert en 2 minutes), pourrais-tu défendre en CAB que ce type de déploiement devienne un **changement standard** ? Écris ton argumentaire en 5 lignes.

---

## Exercice 13.2 — La fiche d'exploitation de taskapi (≈ 30 min)

Rédige `livrables/DEX-taskapi.md` (dossier d'exploitation simplifié) :

- architecture (schéma en Mermaid : Gateway → taskapi → Postgres, Prometheus, Loki…) ;
- composants et versions ;
- procédures : démarrer / arrêter / redémarrer proprement, vérifier la santé (`/healthz`, `/readyz`) ;
- sauvegarde et restauration de la base (CronJob du module 03) ;
- supervision : quelles alertes existent, vers qui elles partent, lien vers les runbooks ;
- consignes en cas d'incident (qui appeler, quoi ne JAMAIS faire, ex. supprimer un PVC) ;
- RTO / RPO visés et comment ils sont atteints.

---

## Exercice 13.3 — Consignes de pilotage d'une chaîne batch (≈ 20 min)

Pour la chaîne `ARRETE_COMPTABLE` que tu construiras au module 14 (attente fichier → contrôle → chargement → soldes → reporting + transfert), écris `livrables/consignes-ARRETE_COMPTABLE.md` : pour **chaque job**, que doit faire le pilote de nuit s'il est en échec ?

| Job | Si échec | Peut être relancé ? | Escalade |
|---|---|---|---|
| attente fichier (timeout) | appeler le partenaire ? | | |
| contrôle fichier | … | | |
| … | | | |

Indice : un job **idempotent** (qu'on peut relancer sans risque) simplifie énormément les consignes. Lesquels le sont ?

---

## Exercice 13.4 — Traduire en vocabulaire « banque » (≈ 10 min)

Réécris en 10 lignes, avec le vocabulaire de ce module (RFC, CAB, MEP, changement standard, PCA/PRA, traçabilité, séparation des tâches), le pitch de 5 minutes du module 11. C'est ce que tu présenteras à un client bancaire.

---

## ✅ Validation

Pas de script : relis tes documents avec la grille ci-dessous.

- [ ] La RFC contient un plan de rollback **avec un déclencheur clair**
- [ ] Le DEX permet à quelqu'un qui ne connaît pas taskapi de le redémarrer et d'en vérifier la santé
- [ ] Les consignes de pilotage indiquent pour chaque job s'il est relançable
- [ ] Le pitch « banque » cite au moins : traçabilité, séparation des tâches, rollback, changement standard
