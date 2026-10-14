# syntax=docker/dockerfile:1
# =============================================================================
# taskapi — image de production
#   docker build -t taskapi:dev --build-arg APP_VERSION=$(git rev-parse --short HEAD) app/
# =============================================================================
ARG PYTHON_VERSION=3.12

# ---------- Étape 1 : construction de l'environnement Python ----------------
FROM python:${PYTHON_VERSION}-slim AS builder

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1

# Un venv isolé, facile à copier tel quel dans l'image finale
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

WORKDIR /build
# Les dépendances d'abord : cette couche n'est reconstruite que si requirements.txt change
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt

# ---------- Étape 2 : image d'exécution minimale ----------------------------
FROM python:${PYTHON_VERSION}-slim AS runtime

ARG APP_VERSION=0.0.0-dev
ARG GIT_SHA=unknown

LABEL org.opencontainers.image.title="taskapi" \
      org.opencontainers.image.description="Application fil rouge du bootcamp DevOps" \
      org.opencontainers.image.source="https://github.com/tadeyayaoye/devops-bootcamp" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    PYTHONPATH=/app/src \
    APP_VERSION=${APP_VERSION}

# Utilisateur dédié, UID numérique fixe (Kubernetes peut vérifier runAsNonRoot)
RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
# Code possédé par root, lisible mais NON modifiable par l'utilisateur d'exécution
COPY src/ ./src/

USER 10001:10001
EXPOSE 8000

# Utilisé par Docker / Compose (Kubernetes utilise ses propres probes)
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD ["python", "-c", "import sys, urllib.request; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=2).status == 200 else 1)"]

# Forme EXEC : uvicorn est PID 1 et reçoit directement SIGTERM
ENTRYPOINT ["uvicorn", "taskapi.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000", "--no-access-log", "--proxy-headers"]
