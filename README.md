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

## Infrastructure

Infrastructure is defined with [OpenTofu](https://opentofu.org/) (HCL is
compatible with Terraform). It needs OpenTofu 1.10 or newer, AWS credentials,
and (for `trivy config`) Trivy.

### State bootstrap

OpenTofu records what it manages in a *state file*. The main stack (added in a
later change) stores its state remotely in S3 so it is shared, versioned and
locked. `infra/bootstrap` creates that bucket once:

```bash
cd infra/bootstrap
tofu init
tofu apply
tofu output state_bucket_name     # the main stack is pointed at this bucket
```

The bucket has versioning, server-side encryption (AES256), all public access
blocked, and a policy that denies non-TLS requests. `prevent_destroy` guards it
against accidental deletion.

Design notes:

- **Chicken-and-egg:** the bucket cannot hold its own state before it exists, so
  this stack uses a local state file (gitignored). If that file is lost, the
  bucket survives and can be re-attached with `tofu import`.
- **No account-specific names in the repo:** the bucket name has a random suffix
  and is supplied to the main stack at `init` time, not committed.
- **Accepted exception:** S3-managed keys (AES256) are used instead of a
  customer-managed KMS key. `trivy config infra` would otherwise flag this
  (AWS-0132); the exception is recorded next to the resource. A production or
  regulated setup should use a KMS key.

Check the code with `tofu fmt -check`, `tofu validate` and
`trivy config --severity HIGH,CRITICAL infra`.

### Main stack: network and image registry

`infra/` holds the main stack, with its state stored in the bootstrap bucket.

```bash
cd infra
cp backend.hcl.example backend.hcl    # set `bucket` to the bootstrap output
tofu init -backend-config=backend.hcl
tofu plan
tofu apply
```

It creates:

- **A VPC** with two public subnets in different availability zones, an internet
  gateway and a route table.
- **Security groups:** the load balancer accepts HTTP from the internet and may
  only talk to the app; the app accepts traffic *only from the load balancer's
  security group* and may only make outbound HTTPS requests. The VPC's default
  security group is emptied.
- **An ECR repository** with immutable tags (a pushed tag can never be
  overwritten), scan-on-push and a lifecycle policy that keeps the last 10 images.

Push the image once the registry exists (needs an AWS login and Docker):

```bash
AWS_PROFILE=<profile> make push              # tag: local-<timestamp>
AWS_PROFILE=<profile> make push TAG=v1       # or choose a tag
```

Design trade-offs, recorded as inline scanner exceptions next to the resources:

- **No NAT gateway.** A NAT gateway costs roughly $30+/month, so tasks will run in
  public subnets and reach ECR and CloudWatch over the internet gateway
  (egress limited to port 443). A production setup should use private subnets with
  VPC endpoints or a NAT gateway so tasks have no public IP.
- **HTTP only** on the load balancer (see below). HTTPS needs a certificate and a
  domain name.

The VPC, subnets, internet gateway, route table and security groups are free;
ECR storage is a few cents per GB-month.

### Load balancer and ECS service

The rest of the main stack runs the container:

- **Application Load Balancer** across both subnets, with a target group that
  health-checks `GET /healthz` every 15 seconds.
- **ECS cluster, task definition and service** on Fargate: two tasks (one per
  availability zone), ARM64, 0.25 vCPU / 0.5 GB each, registered with the load
  balancer. Rolling deployments never drop below the desired count, and a
  deployment circuit breaker rolls back a version that keeps failing.
- **Two IAM roles:** an *execution role* (used by ECS to pull this repository's
  image and write this log group, nothing broader) and a *task role* with no
  permissions, because the application makes no AWS calls.
- **Hardening:** read-only root filesystem, non-root user, security group that
  only admits the load balancer, logs to CloudWatch with 14-day retention.

#### Deploy

`image_tag` has no default, so every deployment names the exact image version.
The registry must exist before an image can be pushed to it, so the first deploy
is done in three steps:

```bash
cd infra
tofu apply -target=aws_ecr_repository.app -target=aws_ecr_lifecycle_policy.app \
  -var image_tag=none                                   # 1. registry only
cd .. && AWS_PROFILE=<profile> make push TAG=v1         # 2. build and push the image
cd infra && tofu apply -var image_tag=v1                # 3. everything else (~5 min)
tofu output app_url                                     # open this in a browser
```

(`-target` is used here only to break the registry/image ordering. Later
deployments are a single `make push` followed by `tofu apply -var image_tag=<tag>`.)

Refreshing the page shows a different `hostname` as the load balancer alternates
between the two tasks.

#### Tear down

```bash
cd infra && tofu destroy -var image_tag=v1
```

This removes every resource in the main stack, including the ECR repository and
its images. The state bucket (bootstrap stack) is left in place.

#### Cost

Billed by the hour while deployed: roughly **$0.06–0.07/hour (about $1.50–1.70 a
day)** in us-west-2, based on list prices (Nov 2026): load balancer $0.0225/h plus
usage, $0.005/h for each public IPv4 address (the load balancer uses two, the
tasks one each), and Fargate ARM at $0.03238 per vCPU-hour and $0.00356 per
GB-hour. Verify against current AWS pricing, and tear the stack down when not in
use.

## Project layout

```
app/main.py        Flask application
tests/             Unit tests (pytest)
gunicorn.conf.py   gunicorn settings
pyproject.toml     Dependencies (ranges); uv.lock pins the exact versions
Dockerfile         Multi-stage image: builder -> test -> runtime
Makefile           test / build / run / scan / push shortcuts
infra/bootstrap/   OpenTofu: S3 bucket for remote state
infra/             OpenTofu main stack: network, ECR, load balancer, IAM, ECS service
```

## Roadmap

- [x] Flask service, tests, locked dependencies
- [x] Container image (multi-stage Dockerfile, non-root, vulnerability scan)
- [x] State backend bootstrap (S3 bucket with versioning, encryption, public access blocked)
- [x] Network and image registry (VPC, subnets, security groups, ECR)
- [x] Load balancer and ECS Fargate service
- [ ] CI/CD with GitHub Actions (OIDC, no stored AWS keys)
- [ ] Architecture diagram, cost notes and design trade-offs
