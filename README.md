# ecs-fargate-terraform-demo

A small Python web service used to practise building a container image and
deploying it to AWS ECS Fargate with OpenTofu (Terraform-compatible).

> **Status: work in progress.** This repository is being built in small,
> reviewable pull requests. The service itself lands first; the container image,
> infrastructure code and CI follow. See the [roadmap](#roadmap).

## The service

A Flask app served by gunicorn. It exposes two endpoints:

| Endpoint | Purpose |
|---|---|
| `GET /healthz` | Liveness check. Returns `{"status": "ok"}`. |
| `GET /` | Reports facts about the environment the process runs in: hostname, pid, uid/gid, kernel, CPU architecture, distro, Python version, build version, CPU count and cgroup limits. Handy for seeing what a container actually looks like from the inside. |

## Run it locally

Requirements: [uv](https://docs.astral.sh/uv/) and Python 3.14.

```bash
uv sync                                  # create .venv from uv.lock
uv run pytest                            # run the tests
uv run gunicorn --config gunicorn.conf.py app.main:application
curl localhost:8000/healthz
```

### Configuration

All optional environment variables:

| Variable | Default | Meaning |
|---|---|---|
| `PORT` | `8000` | Port to listen on |
| `WEB_CONCURRENCY` | `2` | gunicorn worker processes |
| `GUNICORN_THREADS` | `4` | Threads per worker |
| `SERVICE_VERSION` | `dev` | Version label shown by `GET /` |

Worker count is set explicitly rather than derived from the CPU count: inside a
container, `os.cpu_count()` reports the host's CPUs, not the container's limit.

## Project layout

```
app/main.py        Flask application
tests/             Unit tests (pytest)
gunicorn.conf.py   gunicorn settings
pyproject.toml     Dependencies (ranges); uv.lock pins the exact versions
```

## Roadmap

- [x] Flask service, tests, locked dependencies
- [ ] Container image (multi-stage Dockerfile, non-root, vulnerability scan)
- [ ] State backend bootstrap (S3 bucket with versioning, encryption, locking)
- [ ] Network and image registry (VPC, subnets, security groups, ECR)
- [ ] Load balancer and ECS Fargate service
- [ ] CI/CD with GitHub Actions (OIDC, no stored AWS keys)
- [ ] Architecture diagram, cost notes and design trade-offs
