# ecs-fargate-terraform-demo

A small Python web service used to practise building a container image and
deploying it to AWS ECS Fargate with OpenTofu (Terraform-compatible).

> **Status: work in progress.** The service itself lands first; the container
> image, infrastructure code and CI follow. See the [roadmap](#roadmap).

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

## Container image

Requirements: Docker. [Trivy](https://trivy.dev/) for `make scan`.

```bash
make test    # run the unit tests inside the image build (fails the build if they fail)
make build   # build the runtime image (ecs-fargate-demo:dev)
make run     # run it on http://localhost:8000
make scan    # vulnerability scan
```

The [Dockerfile](Dockerfile) has three stages: `builder` (dependencies), `test`
(runs pytest) and `runtime` (the image that ships). Design choices:

- **`python:3.14-slim` (Debian), not Alpine** — most Python binary wheels target
  glibc; musl often forces source builds.
- **Dependencies from `uv.lock`**, installed with `--locked` so a stale lockfile
  fails the build. uv and pip are not present in the final image.
- **Runs as a non-root user** (uid/gid 10001).
- **Exec-form `CMD`** so gunicorn is PID 1 and receives SIGTERM directly;
  `docker stop` returns in well under a second with exit code 0.
- **Dependency layer is cached** and only rebuilt when `pyproject.toml` or
  `uv.lock` change.
- The Dockerfile `HEALTHCHECK` is for local use. Amazon ECS ignores it; health
  checks there come from the task definition and load balancer.

### Vulnerability scan policy

`make scan` fails the build on **fixable** HIGH/CRITICAL findings. The Debian
base image still carries HIGH findings for which no patch exists yet; those are
deliberately not blocking, and are reviewed by rebuilding on a schedule rather
than by suppressing them. Run `trivy image --severity HIGH,CRITICAL
ecs-fargate-demo:dev` to see the full list.

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
Dockerfile         Multi-stage image: builder -> test -> runtime
Makefile           test / build / run / scan shortcuts
```

## Roadmap

- [x] Flask service, tests, locked dependencies
- [x] Container image (multi-stage Dockerfile, non-root, vulnerability scan)
- [ ] State backend bootstrap (S3 bucket with versioning, encryption, locking)
- [ ] Network and image registry (VPC, subnets, security groups, ECR)
- [ ] Load balancer and ECS Fargate service
- [ ] CI/CD with GitHub Actions (OIDC, no stored AWS keys)
- [ ] Architecture diagram, cost notes and design trade-offs
