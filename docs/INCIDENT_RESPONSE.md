# Incident Response Runbook

This runbook covers common local reliability incidents for the DevOps final project stack.

## Quick Triage

Start with these commands:

```bash
docker compose ps
docker compose logs backend
curl http://127.0.0.1:8000/api/health
curl http://127.0.0.1:9090/-/ready
./scripts/validate_environment.sh
```

Use `docker compose logs <service>` for service-specific details:

```bash
docker compose logs frontend
docker compose logs prometheus
docker compose logs loki
docker compose logs grafana
docker compose logs promtail
```

## Common Incidents

### Backend Unhealthy

Symptoms:

- `backend` is `unhealthy` in `docker compose ps`.
- `curl http://127.0.0.1:8000/api/health` fails.
- Frontend API calls fail.

Triage:

```bash
docker compose ps backend
docker compose logs backend
curl --fail http://127.0.0.1:8000/api/health
```

Recovery:

```bash
mkdir -p logs
chmod 777 logs
docker compose restart backend
./scripts/validate_environment.sh
```

If restart does not work:

```bash
docker compose build --pull backend
docker compose up -d backend
./scripts/post_deploy_check.sh
```

### Frontend Unreachable

Symptoms:

- `http://127.0.0.1:3000` does not load.
- `curl http://127.0.0.1:3000/health` fails.
- `frontend` is not healthy.

Triage:

```bash
docker compose ps frontend
docker compose logs frontend
curl --fail http://127.0.0.1:3000/health
```

Recovery:

```bash
docker compose restart frontend
./scripts/validate_environment.sh
```

If the image may be stale:

```bash
docker compose build --pull frontend
docker compose up -d frontend
./scripts/post_deploy_check.sh
```

### Prometheus Target Down

Symptoms:

- Prometheus is ready but the `fastapi-backend` target is down.
- `./scripts/post_deploy_check.sh` reports the Prometheus backend target is not up.

Triage:

```bash
curl --fail http://127.0.0.1:9090/-/ready
curl --fail http://127.0.0.1:8000/metrics
docker compose logs prometheus
```

Recovery:

```bash
docker compose restart prometheus
./scripts/post_deploy_check.sh
```

### Loki Or Logging Unavailable

Symptoms:

- `curl http://127.0.0.1:3100/ready` fails.
- `loki` is unhealthy.
- Promtail cannot send logs.

Triage:

```bash
docker compose ps loki promtail
docker compose logs loki
docker compose logs promtail
curl --fail http://127.0.0.1:3100/ready
```

Recovery:

```bash
docker compose restart loki promtail
./scripts/validate_environment.sh
```

### High Error Rate Alert

Symptoms:

- Prometheus alert rules show elevated backend 5xx responses.
- Backend logs contain repeated `"level":"error"` entries.
- `/api/simulate-error` was called during testing and metrics increased.

Triage:

```bash
docker compose logs backend
curl --fail http://127.0.0.1:8000/metrics
curl --fail http://127.0.0.1:9090/-/ready
```

Recovery:

```bash
docker compose restart backend
./scripts/post_deploy_check.sh
```

If the issue follows a local blue-green deployment:

```bash
./scripts/rollback.sh
./scripts/post_deploy_check.sh
```

## General Recovery Flow

1. Inspect service state:

   ```bash
   docker compose ps
   ```

2. Read logs for the failing service:

   ```bash
   docker compose logs <service>
   ```

3. Restart the failing service:

   ```bash
   docker compose restart <service>
   ```

4. Rebuild and restart the stack if restart is not enough:

   ```bash
   docker compose build --pull
   docker compose up -d
   ```

5. Roll back a failed local blue-green deployment:

   ```bash
   ./scripts/rollback.sh
   ```

6. Confirm recovery:

   ```bash
   ./scripts/post_deploy_check.sh
   ```

## Post-Incident Review Checklist

- What failed first?
- Which service was unhealthy or unreachable?
- Which health endpoint detected the issue?
- What logs or metrics confirmed the cause?
- What recovery action fixed it?
- Was rollback required?
- Should a script, health check, alert, or documentation be improved?
