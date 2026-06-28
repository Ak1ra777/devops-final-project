# Rollback Runbook

This project includes a local blue-green deployment simulation. It is not a full production load balancer, but it demonstrates the same rollback idea: keep two deployable environments, switch the active pointer, and return to the previous environment if the new one is unhealthy.

## How Local Blue-Green Rollback Works

The deployment script uses two local environments:

| Environment | Port |
|---|---:|
| Blue | `8001` |
| Green | `8002` |

The current environment is stored in:

```text
production/current
```

The previous environment is stored in:

```text
production/previous
```

`scripts/rollback.sh` reads those files, checks that the previous environment is healthy, and then swaps the current and previous pointers.

## When To Roll Back

Use rollback when a newly deployed local environment has a clear reliability problem, for example:

- The health endpoint fails.
- The app starts but returns unexpected 5xx errors.
- The frontend cannot reach the backend.
- Post-deploy checks fail after a blue-green deployment.
- A demo or evaluation needs to quickly return to the last known working environment.

## Rollback Command

Run rollback from anywhere inside the repository:

```bash
./scripts/rollback.sh
```

Expected successful output looks like this:

```text
Starting rollback...
Current production: green
Rolling back to: blue
Checking rollback target health...
Rollback successful.
Current production is now: blue
Previous production is now: green
Rollback target health: http://127.0.0.1:8001/api/health
Next validation: ./scripts/post_deploy_check.sh
```

## Validate After Rollback

After rollback, validate the Docker Compose stack and core service endpoints:

```bash
./scripts/post_deploy_check.sh
```

For the blue-green simulation specifically, you can also call the active environment directly:

```bash
cat production/current
curl --fail http://127.0.0.1:8001/api/health
curl --fail http://127.0.0.1:8002/api/health
```

Use the port that matches the active color in `production/current`.

## Limitations

- This is a local simulation, not a real production router.
- The active environment is represented by files under `production/`, not by a live load balancer.
- Rollback only works after at least one successful `./scripts/deploy_blue_green.sh` run.
- The script validates the backend health endpoint, but it does not migrate databases or user traffic.
- Docker Compose services are validated separately by `./scripts/validate_environment.sh` and `./scripts/post_deploy_check.sh`.
