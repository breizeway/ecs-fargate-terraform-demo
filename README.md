# ecs-fargate-terraform-demo

A small Python web service, packaged as a container image and deployed to AWS ECS
Fargate with [OpenTofu](https://opentofu.org/) (Terraform-compatible), behind a
load balancer with HTTPS. A learning project.

> **Status:** working end to end (image, infrastructure, CI/CD, HTTPS).

## The service

A Flask app served by gunicorn.

| Endpoint | Returns |
|---|---|
| `GET /health` | `{"status": "ok"}` (the load balancer's health check) |
| `GET /` | Where the service is running, as JSON: `version`, user and process ids, `os`, `system` and the Python version. `system.node` is the name of the container that answered, so it alternates when two are running. |

Environment variables (all optional): `PORT` (8000), `WEB_CONCURRENCY` (2 gunicorn
workers), `GUNICORN_THREADS` (4), `SERVICE_VERSION` (`dev`, shown by `GET /`).

## Run it locally

Requires [uv](https://docs.astral.sh/uv/) and Python 3.14.

```bash
uv sync                                  # create .venv from uv.lock
uv run pytest                            # run the tests
uv run gunicorn --config gunicorn.conf.py app.main:application
curl localhost:8000/health
```

## Container image

Requires Docker, and [Trivy](https://trivy.dev/) for `make scan`.

```bash
make test    # run the unit tests inside the image build (fails the build if they fail)
make build   # build the runtime image (ecs-fargate-demo:dev)
make run     # run it on http://localhost:8000
make scan    # vulnerability scan
```

The [Dockerfile](Dockerfile) has three stages: `builder` (installs dependencies),
`test` (runs pytest) and `runtime` (the image that ships). The image runs as a
non-root user, installs dependencies from `uv.lock` (uv and pip are not in the
final image), and uses an exec-form `CMD` so gunicorn receives the stop signal
directly (in a test, `docker stop` finished in well under a second with exit
code 0).

**Scan policy:** `make scan` fails on HIGH/CRITICAL findings that already have a
patch. The Debian base image can also carry HIGH findings with no patch yet; those
do not fail the build, because rebuilding cannot remove them. Nothing is
suppressed and nothing re-scans on a timer, so re-run the scan after each base
image update. To list everything: `trivy image --severity HIGH,CRITICAL ecs-fargate-demo:dev`.

## Infrastructure

Needs OpenTofu 1.10 or newer and AWS credentials. Two stacks:

- `infra/bootstrap/`: the S3 bucket that stores state, and the IAM role GitHub
  Actions uses to deploy. Applied once, by hand, with local state (the bucket
  can't hold its own state before it exists).
- `infra/`: everything else. One file per AWS area: `network.tf`,
  `security_groups.tf`, `ecr.tf`, `load_balancer.tf`, `certificate.tf`, `iam.tf`,
  `ecs.tf`.

What the main stack creates:

- A VPC with two public subnets in different availability zones.
- Security groups: the load balancer accepts web traffic from the internet; the app
  accepts traffic only from the load balancer.
- An ECR repository with immutable tags and scan-on-push.
- An Application Load Balancer: HTTPS on 443, and port 80 redirects to it.
- An ECS Fargate service: two ARM64 tasks (one per zone) with rolling deployments
  and automatic rollback of a version that keeps failing. Logs go to CloudWatch.
- An ACM certificate for the site's domain.

Public subnets with no NAT gateway keep the cost down. A production setup should
use private subnets with VPC endpoints or a NAT gateway.

### Set up

```bash
cd infra/bootstrap && tofu init && tofu apply     # state bucket, once
tofu output state_bucket_name

cd ..                                             # now in infra/
cp backend.hcl.example backend.hcl                # set `bucket` to the output above
tofu init -backend-config=backend.hcl
```

### Deploy by hand

`image_tag` has no default, so every deploy names the exact image version. The
registry must exist before an image can be pushed to it, so the first deploy
takes three steps:

```bash
tofu apply -target=aws_ecr_repository.app -target=aws_ecr_lifecycle_policy.app \
  -var image_tag=none                                   # 1. registry only
cd .. && AWS_PROFILE=<profile> make push TAG=v1         # 2. build and push the image
cd infra && tofu apply -var image_tag=v1                # 3. everything else
tofu output app_url
```

Later deploys are one `make push TAG=<tag>` followed by `tofu apply -var image_tag=<tag>`.

While deployed, `curl https://<domain_name>/` returns the `GET /` JSON, and
`make check` makes 6 requests so you can see `system.node` alternate.

### Deploy with GitHub Actions

Pushing a tag like `v6` (on a commit that is on `main`) runs
`.github/workflows/deploy.yml`: tests, scan, push to ECR, `tofu plan`, then
`tofu apply` after a manual approval (the `production` environment), then a smoke
test of the live site. AWS access is a short-lived OIDC credential; no keys are
stored. It needs two repository secrets, `AWS_DEPLOY_ROLE_ARN` and
`TF_STATE_BUCKET`. `ci.yml` runs the tests, the image scan and the OpenTofu checks
(`fmt`, `validate`, `trivy config`) on every pull request.

### Custom domain and HTTPS

The site is served at `https://<domain_name>` (default
`ecs-fargate-terraform-demo.tannor.net`, in `variables.tf`). The parent domain's DNS
is hosted outside AWS and its provider has no `NS` record type, so two `CNAME`
records are added by hand:

1. `tofu apply` requests the ACM certificate and waits for it to validate.
2. While it waits, read the validation record and add it as a `CNAME`:
   ```bash
   CERT=$(aws acm list-certificates --region us-west-2 \
     --certificate-statuses PENDING_VALIDATION ISSUED \
     --query "CertificateSummaryList[?DomainName=='<domain_name>'].CertificateArn" --output text)
   aws acm describe-certificate --region us-west-2 --certificate-arn "$CERT" \
     --query 'Certificate.DomainValidationOptions[0].ResourceRecord'
   ```
3. When the apply finishes, add a second `CNAME` from the site's name to
   `tofu output -raw load_balancer_dns_name`.

Keep the validation record: ACM uses it to renew the certificate.

### Tear down

```bash
cd infra && tofu destroy -var image_tag=v1
```

This removes the whole main stack, including the ECR repository, its images and
the certificate. The state bucket is left in place, and the two `CNAME` records
must be removed by hand.

### Cost

Roughly **$0.06–0.07 an hour (about $1.50–1.70 a day)** in us-west-2 while
deployed, from list prices in Nov 2026: load balancer $0.0225/h plus usage,
$0.005/h per public IPv4 address (two for the load balancer, one per task), and
Fargate ARM at $0.03238 per vCPU-hour and $0.00356 per GB-hour. The ACM
certificate is free. Check current AWS pricing, and tear the stack down when not
in use.

## Project layout

```
app/main.py        Flask application
tests/             Unit tests (pytest)
gunicorn.conf.py   gunicorn settings
pyproject.toml     Dependencies; uv.lock pins the exact versions
Dockerfile         Multi-stage image: builder -> test -> runtime
Makefile           test / build / run / scan / push / check shortcuts
infra/bootstrap/   OpenTofu: state bucket and the GitHub deploy role
infra/             OpenTofu main stack
.github/workflows/ ci.yml (checks) and deploy.yml (release on a v* tag)
```
