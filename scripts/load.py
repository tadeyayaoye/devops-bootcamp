#!/usr/bin/env python3
"""Générateur de charge minimaliste (bibliothèque standard uniquement).

    python3 scripts/load.py http://taskapi-dev.localhost --duration 120 --concurrency 5

Mélange de lectures/écritures sur l'API taskapi pour alimenter métriques, logs et traces.
Les noms en *.localhost sont résolus vers 127.0.0.1 (Python ne le fait pas tout seul,
contrairement à curl et aux navigateurs) en gardant le bon en-tête Host pour la Gateway.
"""
from __future__ import annotations

import argparse
import json
import random
import threading
import time
import urllib.error
import urllib.request
from collections import Counter
from urllib.parse import urlsplit, urlunsplit

stats: Counter[str] = Counter()
lock = threading.Lock()


def target(base_url: str) -> tuple[str, str]:
    parts = urlsplit(base_url.rstrip("/"))
    host = parts.hostname or "localhost"
    if host.endswith(".localhost"):
        netloc = "127.0.0.1" + (f":{parts.port}" if parts.port else "")
        return urlunsplit((parts.scheme, netloc, parts.path, "", "")), parts.netloc
    return base_url.rstrip("/"), parts.netloc


def call(base: str, host: str, method: str, path: str, body: dict | None = None) -> int:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(base + path, data=data, method=method)
    req.add_header("Host", host)
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status
    except urllib.error.HTTPError as exc:
        return exc.code
    except Exception:  # noqa: BLE001 - un générateur de charge ne doit jamais s'arrêter
        return 0


def worker(base: str, host: str, deadline: float) -> None:
    while time.time() < deadline:
        r = random.random()
        if r < 0.6:
            status = call(base, host, "GET", "/api/tasks?limit=20")
        elif r < 0.85:
            status = call(base, host, "POST", "/api/tasks", {"title": f"tâche {random.randint(1, 10_000)}"})
        elif r < 0.95:
            status = call(base, host, "GET", f"/api/tasks/{random.randint(1, 50)}")
        else:
            status = call(base, host, "GET", "/n-existe-pas")
        with lock:
            stats[str(status)] += 1
        time.sleep(random.uniform(0.02, 0.2))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("url", help="ex. http://taskapi-dev.localhost ou http://localhost:8000")
    parser.add_argument("--duration", type=int, default=60, help="durée en secondes")
    parser.add_argument("--concurrency", type=int, default=5, help="nombre de threads")
    args = parser.parse_args()

    base, host = target(args.url)
    deadline = time.time() + args.duration
    print(f"→ charge sur {args.url} pendant {args.duration}s avec {args.concurrency} threads…")
    threads = [threading.Thread(target=worker, args=(base, host, deadline), daemon=True) for _ in range(args.concurrency)]
    for t in threads:
        t.start()
    try:
        while any(t.is_alive() for t in threads):
            time.sleep(5)
            with lock:
                print("  codes HTTP :", dict(sorted(stats.items())), flush=True)
    except KeyboardInterrupt:
        print("interrompu")
    print("Terminé :", dict(sorted(stats.items())))


if __name__ == "__main__":
    main()
