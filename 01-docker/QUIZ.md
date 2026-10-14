# Module 01 — Quiz Docker

<details><summary>1. Quelle est la différence fondamentale entre un conteneur et une VM ?</summary>

Une VM virtualise du matériel et embarque son propre noyau (isolation forte, démarrage en secondes/minutes, Go de RAM). Un conteneur est un processus de l'hôte isolé par des **namespaces** (ce qu'il voit) et limité par des **cgroups** (ce qu'il consomme), partageant le noyau de l'hôte (démarrage en ms, overhead quasi nul, isolation plus faible : une faille noyau touche tous les conteneurs). D'où les runtimes sandboxés (gVisor, Kata Containers) pour le multi-tenant hostile.
</details>

<details><summary>2. Un conteneur s'arrête avec le code 137. Que s'est-il passé ? Comment le confirmer ?</summary>

137 = 128 + 9 → il a reçu SIGKILL. Le plus souvent : **OOM kill** (dépassement de la limite mémoire du cgroup), ou fin du délai de grâce après un SIGTERM ignoré. Confirmer : `docker inspect <c> --format '{{.State.OOMKilled}}'`, `dmesg`, `docker events`. Dans Kubernetes : `kubectl describe pod` → `Last State: Terminated, Reason: OOMKilled`.
</details>

<details><summary>3. Pourquoi l'ordre des instructions d'un Dockerfile impacte-t-il la durée de build ?</summary>

Chaque instruction produit une couche mise en cache ; dès qu'une couche est invalidée (instruction ou fichiers copiés modifiés), toutes les suivantes sont reconstruites. On place donc ce qui change rarement (base, dépendances système, `requirements.txt` + `pip install`) avant ce qui change souvent (le code source).
</details>

<details><summary>4. ENTRYPOINT vs CMD ? Forme exec vs forme shell ?</summary>

ENTRYPOINT définit l'exécutable, CMD les arguments par défaut (remplacés par ceux de `docker run image args`). Forme exec (`["bin","arg"]`) : le binaire est PID 1 et reçoit les signaux. Forme shell (`bin arg`) : lancé via `/bin/sh -c`, c'est `sh` qui est PID 1 et qui ne relaie pas SIGTERM → arrêt brutal après le délai de grâce.
</details>

<details><summary>5. J'ai fait <code>COPY .env .</code> puis <code>RUN rm .env</code>. Le secret est-il dans l'image ?</summary>

Oui. La couche du COPY contient toujours le fichier ; le RUN suivant ajoute seulement une couche qui le masque. N'importe qui peut extraire les couches (`docker save`, `dive`, `crane export`). Solutions : `.dockerignore`, secrets BuildKit (`RUN --mount=type=secret`), injection au runtime (variables, fichiers montés, gestionnaire de secrets).
</details>

<details><summary>6. ARG ou ENV pour passer un mot de passe ?</summary>

Ni l'un ni l'autre. ARG est visible dans `docker history` et les métadonnées de build ; ENV est persisté dans l'image (visible via `docker inspect`). Au build : `--mount=type=secret`. Au runtime : variable d'environnement injectée par l'orchestrateur depuis un Secret, ou mieux un fichier monté (`/run/secrets/...`).
</details>

<details><summary>7. Pourquoi les conteneurs d'un même <code>compose.yaml</code> peuvent-ils se joindre par leur nom, mais pas ceux lancés avec un simple <code>docker run</code> ?</summary>

Compose crée un **réseau bridge défini par l'utilisateur**, qui embarque un serveur DNS interne (127.0.0.11) résolvant les noms de services/conteneurs. Le bridge par défaut (`docker0`) n'a pas cette résolution de noms. On peut faire pareil à la main : `docker network create monreseau` + `--network monreseau`.
</details>

<details><summary>8. <code>depends_on</code> garantit-il que Postgres est prêt quand l'API démarre ?</summary>

Pas par défaut : il garantit seulement l'ordre de démarrage des conteneurs. Avec `condition: service_healthy`, Compose attend que le healthcheck de la base soit OK. Et l'application doit de toute façon savoir réessayer (taskapi réessaie dans `create_schema`) : en production, une dépendance peut tomber à tout moment. Kubernetes, lui, n'a pas d'ordre de démarrage entre déploiements : la readiness et les retries font le travail.
</details>

<details><summary>9. Pourquoi éviter Alpine pour une image Python ?</summary>

Alpine utilise musl au lieu de glibc : la plupart des wheels précompilées (manylinux) ne s'installent pas, pip compile depuis les sources (builds longs, nécessite gcc/headers), images finalement pas plus petites, et différences de comportement (résolution DNS, performances de l'allocateur). `-slim` (Debian) ou distroless sont de meilleurs choix.
</details>

<details><summary>10. Qu'apporte un multi-stage build ?</summary>

Séparer l'environnement de construction (compilateurs, caches, dépendances de dev, outils) de l'image d'exécution qui ne contient que l'artefact final. Résultat : image plus petite, moins de CVE, moins d'outils exploitables par un attaquant, et builds plus clairs.
</details>

<details><summary>11. Pourquoi tagger les images avec le SHA du commit plutôt que <code>latest</code> ?</summary>

Traçabilité (on sait exactement quel code tourne), immutabilité (le tag ne bouge pas), rollback fiable (redéployer le tag précédent), et les orchestrateurs détectent le changement de spec (changer `latest` → `latest` ne déclenche aucun rollout dans Kubernetes). Encore mieux : référencer par digest `@sha256:`.
</details>

<details><summary>12. Que fait <code>--cap-drop ALL</code> et pourquoi ?</summary>

Les privilèges de root sont découpés en *capabilities* (CAP_NET_ADMIN, CAP_SYS_ADMIN, CAP_CHOWN…). Docker en accorde un sous-ensemble par défaut. Les retirer toutes réduit drastiquement ce qu'un attaquant peut faire en cas de compromission ; on rajoute uniquement le nécessaire (ex. `NET_BIND_SERVICE` pour écouter sur un port < 1024 sans être root).
</details>

<details><summary>13. Différence entre volume nommé et bind mount ?</summary>

Le volume nommé est géré par Docker (emplacement, cycle de vie, drivers possibles : NFS, cloud…), portable, idéal pour les données applicatives. Le bind mount monte un chemin précis de l'hôte : pratique en dev (code monté pour le hot reload) ou pour injecter une config, mais dépendant de l'hôte et de ses permissions/UID.
</details>

<details><summary>14. Qu'est-ce qu'un SBOM et à quoi sert-il concrètement ?</summary>

Software Bill of Materials : inventaire exhaustif des composants (paquets OS, librairies, versions, licences) d'un artefact, aux formats SPDX ou CycloneDX. Quand une nouvelle CVE sort (ex. Log4Shell), on sait en minutes quelles images sont concernées sans tout rescanner ; c'est aussi exigé par certaines réglementations (Cyber Resilience Act en Europe, décret US EO 14028).
</details>

<details><summary>15. Kubernetes utilise-t-il Docker ?</summary>

Plus depuis la v1.24 (suppression du dockershim). Le kubelet parle à un runtime compatible CRI : containerd (le plus courant, que Docker utilise lui-même en interne) ou CRI-O. Les images construites avec Docker sont des images OCI standard, donc parfaitement compatibles.
</details>
