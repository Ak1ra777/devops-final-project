# Service Level Objectives

These SLOs are designed for local evaluation and demos. They are intentionally simple and measurable with the Docker Compose stack, health endpoints, logs, and Prometheus metrics included in this project.

## Availability Objective

Target:

```text
99% availability during local demo/runtime windows
```

A service is considered available when the expected health or readiness endpoint returns a successful response.

Measured endpoints:

| Component | Endpoint |
|---|---|
| Backend | `http://127.0.0.1:8000/api/health` |
| Frontend | `http://127.0.0.1:3000/health` |
| Prometheus | `http://127.0.0.1:9090/-/ready` |
| Loki | `http://127.0.0.1:3100/ready` |
| Grafana | `http://127.0.0.1:3001/api/health` |

Validation command:

```bash
./scripts/validate_environment.sh
```

## Error-Rate Objective

Target:

```text
Backend 5xx responses stay below 1% of total backend requests during a demo/runtime window.
```

Signals:

- Backend logs written to `logs/backend.log`.
- Prometheus metrics from `http://127.0.0.1:8000/metrics`.
- `app_requests_total` and `app_errors_total` counters.

The `/api/simulate-error` endpoint intentionally creates a 500 response for testing. Those test calls should be excluded from normal demo reliability expectations when they are triggered deliberately.

## Latency Objective

Target:

```text
95% of backend health and API requests complete under 500 ms during local demo/runtime.
```

Signals:

- `app_request_duration_seconds` Prometheus histogram.
- Local `curl` checks from validation scripts.
- User-visible frontend responsiveness during local testing.

## Alerting Strategy

Prometheus loads alert rules from:

```text
monitoring/prometheus/alert_rules.yml
```

Local alerting should focus on:

- Backend service unavailable.
- High backend 5xx error rate.
- Prometheus target down.
- Loki unavailable.
- Grafana unavailable.

Use these commands to check alert and target health:

```bash
curl --fail http://127.0.0.1:9090/-/ready
curl --fail http://127.0.0.1:9090/api/v1/targets
./scripts/post_deploy_check.sh
```

## What Counts As Downtime

For this project, downtime means one or more of these conditions during an expected running window:

- Backend `/api/health` fails.
- Frontend `/health` fails or the frontend is unreachable.
- Prometheus readiness fails.
- Loki readiness fails.
- Grafana health fails.
- Prometheus cannot scrape the backend target after the stack has had time to start.

Planned local shutdowns do not count as downtime:

```bash
docker compose down -v --remove-orphans
```

## Operational Commands

Start and validate the stack:

```bash
./scripts/run_local.sh
```

Run post-deploy checks:

```bash
./scripts/post_deploy_check.sh
```

Monitor the active local deployment or Compose backend:

```bash
./scripts/monitor.sh 2 2
```
