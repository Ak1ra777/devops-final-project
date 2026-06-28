import json
import logging
import os
import sys
from datetime import UTC, datetime
from pathlib import Path
from time import perf_counter
from typing import Literal

from fastapi import FastAPI, HTTPException, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from pydantic import BaseModel, Field
from starlette.types import ASGIApp, Message, Receive, Scope, Send


def default_log_file_path() -> Path:
    app_dir = Path(__file__).resolve().parent

    if app_dir.name == "backend":
        return app_dir.parent / "logs" / "backend.log"

    return app_dir / "logs" / "backend.log"


LOG_FILE_PATH = Path(os.getenv("BACKEND_LOG_FILE", default_log_file_path()))
LOG_FILE_PATH.parent.mkdir(parents=True, exist_ok=True)

request_logger = logging.getLogger("backend.requests")
request_logger.setLevel(logging.INFO)
request_logger.propagate = False

if not request_logger.handlers:
    log_formatter = logging.Formatter("%(message)s")

    stdout_handler = logging.StreamHandler(sys.stdout)
    stdout_handler.setFormatter(log_formatter)

    file_handler = logging.FileHandler(LOG_FILE_PATH, encoding="utf-8")
    file_handler.setFormatter(log_formatter)

    request_logger.addHandler(stdout_handler)
    request_logger.addHandler(file_handler)


REQUESTS_TOTAL = Counter(
    "app_requests_total",
    "Total HTTP requests processed by the FastAPI app.",
    ["method", "path", "status_code"],
)
ERRORS_TOTAL = Counter(
    "app_errors_total",
    "Total HTTP requests that returned server errors.",
    ["method", "path", "status_code"],
)
REQUEST_DURATION_SECONDS = Histogram(
    "app_request_duration_seconds",
    "HTTP request duration in seconds.",
    ["method", "path"],
)
DEPLOYMENTS_CREATED_TOTAL = Counter(
    "app_deployments_created_total",
    "Total deployments created through the API.",
)


def get_route_path(scope: Scope) -> str:
    route = scope.get("route")
    route_path = getattr(route, "path", None)

    return route_path or str(scope.get("path", "unknown"))


def write_request_log(
    *,
    method: str,
    path: str,
    status_code: int,
    duration_ms: float,
) -> None:
    level = "error" if status_code >= 500 else "info"
    message = "request failed" if status_code >= 500 else "request completed"
    log_entry = {
        "timestamp": datetime.now(UTC).isoformat(),
        "level": level,
        "message": message,
        "method": method,
        "path": path,
        "status_code": status_code,
        "duration_ms": round(duration_ms, 2),
    }

    if status_code >= 500:
        request_logger.error(json.dumps(log_entry))
    else:
        request_logger.info(json.dumps(log_entry))


class ObservabilityMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        started_at = perf_counter()
        method = str(scope.get("method", "UNKNOWN"))
        status_code = 500

        async def send_wrapper(message: Message) -> None:
            nonlocal status_code

            if message["type"] == "http.response.start":
                status_code = int(message["status"])

            await send(message)

        try:
            await self.app(scope, receive, send_wrapper)
        except Exception:
            status_code = 500
            raise
        finally:
            record_observability(
                method=method,
                path=get_route_path(scope),
                status_code=status_code,
                duration_seconds=perf_counter() - started_at,
            )


def record_observability(
    *,
    method: str,
    path: str,
    status_code: int,
    duration_seconds: float,
) -> None:
    status_code_label = str(status_code)

    REQUESTS_TOTAL.labels(
        method=method,
        path=path,
        status_code=status_code_label,
    ).inc()
    REQUEST_DURATION_SECONDS.labels(method=method, path=path).observe(
        duration_seconds
    )

    if status_code >= 500:
        ERRORS_TOTAL.labels(
            method=method,
            path=path,
            status_code=status_code_label,
        ).inc()

    write_request_log(
        method=method,
        path=path,
        status_code=status_code,
        duration_ms=duration_seconds * 1000,
    )


app = FastAPI(title="DevOps Midterm API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(ObservabilityMiddleware)

STARTED_AT = datetime.now(UTC)
FRONTEND_DIST_DIR = Path(__file__).resolve().parent.parent / "frontend" / "dist"
FRONTEND_ASSETS_DIR = FRONTEND_DIST_DIR / "assets"
FRONTEND_INDEX_FILE = FRONTEND_DIST_DIR / "index.html"


class DeploymentCreate(BaseModel):
    version: str = Field(min_length=1, max_length=50)
    environment: Literal["staging", "production"]
    status: Literal["pending", "running", "success", "failed"]
    owner: str = Field(min_length=1, max_length=50)


deployments = [
    {
        "version": "v1.0.0",
        "environment": "production",
        "status": "success",
        "owner": "release-bot",
        "created_at": "2026-05-02T10:00:00Z",
    },
    {
        "version": "v1.1.0",
        "environment": "staging",
        "status": "running",
        "owner": "dev-team",
        "created_at": "2026-05-02T11:30:00Z",
    },
]


@app.get("/metrics", include_in_schema=False)
def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/api/health")
def health_check():
    return {
        "status": "ok",
        "service": app.title,
        "timestamp": datetime.now(UTC).isoformat(),
        "uptime_seconds": int((datetime.now(UTC) - STARTED_AT).total_seconds()),
    }


@app.get("/api/ready")
def readiness_check():
    return {
        "status": "ready",
        "deployment_count": len(deployments),
        "timestamp": datetime.now(UTC).isoformat(),
    }


@app.get("/api/deployments")
def list_deployments():
    return {"items": deployments, "count": len(deployments)}


@app.get("/api/simulate-error")
def simulate_error():
    raise HTTPException(status_code=500, detail="Simulated internal server error")


@app.get("/api/deployments/{version}")
def get_deployment(version: str):
    for deployment in deployments:
        if deployment["version"] == version:
            return deployment

    raise HTTPException(status_code=404, detail="Deployment not found")


@app.post("/api/deployments", status_code=201)
def create_deployment(payload: DeploymentCreate):
    deployment = {
        "version": payload.version,
        "environment": payload.environment,
        "status": payload.status,
        "owner": payload.owner,
        "created_at": datetime.now(UTC).isoformat(),
    }

    deployments.append(deployment)
    DEPLOYMENTS_CREATED_TOTAL.inc()

    return deployment


if FRONTEND_ASSETS_DIR.is_dir():
    app.mount(
        "/assets",
        StaticFiles(directory=FRONTEND_ASSETS_DIR),
        name="frontend-assets",
    )


def frontend_build_exists():
    return FRONTEND_INDEX_FILE.is_file()


@app.get("/{frontend_path:path}", include_in_schema=False)
def serve_frontend(frontend_path: str):
    if frontend_path == "api" or frontend_path.startswith("api/"):
        raise HTTPException(status_code=404, detail="Not found")

    if not frontend_build_exists():
        raise HTTPException(status_code=404, detail="Not found")

    frontend_root = FRONTEND_DIST_DIR.resolve()
    requested_path = (FRONTEND_DIST_DIR / frontend_path).resolve()

    try:
        requested_path.relative_to(frontend_root)
    except ValueError:
        raise HTTPException(status_code=404, detail="Not found") from None

    if requested_path.is_file():
        return FileResponse(requested_path)

    return FileResponse(FRONTEND_INDEX_FILE)
