from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response, status
from fastapi.responses import JSONResponse
from sqlalchemy import select
from sqlalchemy.orm import Session

from .db import get_session
from .metrics import TASKS_CREATED, ChaosState, metrics_response
from .models import Task
from .schemas import ChaosConfig, TaskCreate, TaskOut, TaskUpdate

router = APIRouter()
SessionDep = Annotated[Session, Depends(get_session)]


# --- Exploitation ------------------------------------------------------------------

@router.get("/", tags=["ops"])
def root(request: Request) -> dict:
    s = request.app.state.settings
    return {"service": s.app_name, "version": s.app_version, "env": s.app_env, "docs": "/docs"}


@router.get("/healthz", tags=["ops"])
def healthz() -> dict:
    """Liveness : répond tant que le process tourne. Ne teste AUCUNE dépendance,
    sinon une panne de base ferait redémarrer en boucle tous les pods (inutile)."""
    return {"status": "ok"}


@router.get("/readyz", tags=["ops"])
def readyz(request: Request):
    """Readiness : l'instance peut-elle servir du trafic ? Si la base ne répond pas,
    Kubernetes retire le pod des endpoints du Service (sans le redémarrer)."""
    try:
        request.app.state.db.ping()
    except Exception as exc:  # noqa: BLE001
        return JSONResponse({"status": "not ready", "reason": str(exc).splitlines()[0]}, status_code=503)
    return {"status": "ready"}


@router.get("/version", tags=["ops"])
def version(request: Request) -> dict:
    s = request.app.state.settings
    return {"version": s.app_version, "env": s.app_env}


@router.get("/metrics", tags=["ops"], include_in_schema=False)
def metrics() -> Response:
    return metrics_response()


# --- Métier ------------------------------------------------------------------------

@router.get("/api/tasks", response_model=list[TaskOut], tags=["tasks"])
def list_tasks(
    session: SessionDep,
    done: bool | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
):
    stmt = select(Task).order_by(Task.id).limit(limit).offset(offset)
    if done is not None:
        stmt = stmt.where(Task.done == done)
    return session.scalars(stmt).all()


@router.post("/api/tasks", response_model=TaskOut, status_code=status.HTTP_201_CREATED, tags=["tasks"])
def create_task(payload: TaskCreate, session: SessionDep):
    task = Task(title=payload.title, description=payload.description)
    session.add(task)
    session.commit()
    session.refresh(task)
    TASKS_CREATED.inc()
    return task


def _get_or_404(session: Session, task_id: int) -> Task:
    task = session.get(Task, task_id)
    if task is None:
        raise HTTPException(status_code=404, detail=f"tâche {task_id} introuvable")
    return task


@router.get("/api/tasks/{task_id}", response_model=TaskOut, tags=["tasks"])
def get_task(task_id: int, session: SessionDep):
    return _get_or_404(session, task_id)


@router.patch("/api/tasks/{task_id}", response_model=TaskOut, tags=["tasks"])
def update_task(task_id: int, payload: TaskUpdate, session: SessionDep):
    task = _get_or_404(session, task_id)
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(task, field, value)
    session.commit()
    session.refresh(task)
    return task


@router.delete("/api/tasks/{task_id}", status_code=status.HTTP_204_NO_CONTENT, tags=["tasks"])
def delete_task(task_id: int, session: SessionDep) -> Response:
    task = _get_or_404(session, task_id)
    session.delete(task)
    session.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# --- Chaos engineering (modules 09-11) ----------------------------------------------

def _chaos_or_404(request: Request) -> ChaosState:
    if not request.app.state.settings.chaos_enabled:
        raise HTTPException(status_code=404, detail="chaos désactivé (CHAOS_ENABLED=false)")
    return request.app.state.chaos


@router.get("/chaos", response_model=ChaosConfig, tags=["chaos"])
def get_chaos(request: Request):
    chaos = _chaos_or_404(request)
    return ChaosConfig(error_rate=chaos.error_rate, latency_ms=chaos.latency_ms)


@router.put("/chaos", response_model=ChaosConfig, tags=["chaos"])
def set_chaos(payload: ChaosConfig, request: Request):
    chaos = _chaos_or_404(request)
    chaos.error_rate = payload.error_rate
    chaos.latency_ms = payload.latency_ms
    return payload
