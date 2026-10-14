# Postmortem — <titre court de l'incident>

> **Sans reproche (blameless)** : on cherche ce qui, dans le système et les processus, a permis l'incident — pas un coupable. Les personnes ont agi au mieux avec les informations qu'elles avaient.

| | |
|---|---|
| **Date** | AAAA-MM-JJ |
| **Auteur(s)** | |
| **Statut** | brouillon / revu / clos |
| **Sévérité** | SEV1 (prod indisponible) · SEV2 (dégradation majeure) · SEV3 (mineure) |
| **Durée d'impact** | de HH:MM à HH:MM (xx min) |
| **Budget d'erreur consommé** | xx % du budget mensuel |

## Résumé

3-4 phrases : ce qui s'est passé, l'impact pour les utilisateurs, comment ça a été résolu.

## Impact

- Utilisateurs/requêtes touchés (chiffres issus des métriques) :
- Fonctionnalités indisponibles :
- SLO concernés :

## Chronologie (heure locale)

| Heure | Événement |
|---|---|
| HH:MM | Déploiement de … (commit, PR) |
| HH:MM | Première erreur visible dans les métriques |
| HH:MM | **Détection** : alerte `…` (ou signalement utilisateur ← à améliorer) |
| HH:MM | Prise en charge par … |
| HH:MM | Hypothèse 1 … (infirmée par …) |
| HH:MM | Cause identifiée : … |
| HH:MM | **Mitigation** : rollback / revert / désactivation du chaos… |
| HH:MM | Retour à la normale confirmé (métriques, SLO) |

Indicateurs : **MTTD** (détection) = … min · **MTTR** (restauration) = … min

## Cause racine et facteurs contributifs

Utilise les « 5 pourquoi » :
1. Pourquoi les requêtes échouaient-elles ? …
2. Pourquoi … ?
3. …

Facteurs contributifs (tests manquants, alerte absente, revue insuffisante, documentation…) :

## Ce qui a bien fonctionné

-

## Ce qui a moins bien fonctionné

-

## Où avons-nous eu de la chance ?

-

## Actions correctives

| Action | Type (prévenir / détecter / atténuer) | Responsable | Échéance | Ticket |
|---|---|---|---|---|
| | | | | |

## Annexes

Liens : dashboards (captures), requêtes PromQL/LogQL utilisées, trace ID représentatif, commits/PR concernés, fil de discussion de l'incident.
