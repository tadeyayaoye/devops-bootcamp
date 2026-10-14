# Docker — fiche mémo

```bash
# Images
docker build -t app:dev --build-arg V=1 -f Dockerfile .     docker images / image ls
docker history --no-trunc app:dev                            docker image inspect app:dev | jq '.[0].Config'
docker tag app:dev ghcr.io/u/app:1a2b3c4                     docker push / pull
docker buildx build --platform linux/amd64,linux/arm64 --push -t … .
docker image prune -a                                        docker system df / prune

# Conteneurs
docker run -d --name c -p 127.0.0.1:8000:8000 -e K=V --rm app:dev
docker run --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges --user 10001 -m 256m --cpus 0.5 app
docker ps -a                     docker logs -f --tail 100 c        docker exec -it c sh
docker inspect c --format '{{.State.ExitCode}} {{.State.OOMKilled}} {{.State.Health.Status}}'
docker stats --no-stream         docker top c                        docker diff c
docker stop -t 30 c              docker rm -f c                      docker events

# Réseau / volumes
docker network create n          docker network inspect n            docker run --network container:<c> nicolaka/netshoot
docker volume ls / inspect / rm  docker run --rm -v vol:/data -v $PWD:/b alpine tar czf /b/vol.tgz -C /data .

# Compose
docker compose up -d --build     docker compose ps / logs -f svc / exec svc sh
docker compose config            docker compose down (-v : ⚠ volumes)
docker compose --profile p up -d docker compose restart svc
```

**Dockerfile** : `FROM … AS build` → `COPY requirements` → `RUN install` → `COPY src` → `FROM slim` → `COPY --from=build` → `USER 10001` → `HEALTHCHECK` → `ENTRYPOINT ["exec","form"]`.

Codes de sortie : 0 OK · 1 appli · 125 Docker · 126 non exécutable · 127 introuvable · **137 SIGKILL/OOM** · 143 SIGTERM.

Sécurité : `hadolint Dockerfile` · `trivy image --severity CRITICAL --ignore-unfixed --exit-code 1 img` · `trivy image --format cyclonedx img > sbom.json`.
