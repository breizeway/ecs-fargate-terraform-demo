IMAGE   ?= ecs-fargate-demo
VERSION ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo dev)
PORT    ?= 8000

.DEFAULT_GOAL := help
.PHONY: help test build run scan

help: ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-8s %s\n", $$1, $$2}'

test: ## Run unit tests inside the image build (always re-runs; fails the build on failure)
	docker build --target test --no-cache-filter test --progress=plain -t $(IMAGE):test .

build: ## Build the runtime image
	docker build --target runtime --build-arg SERVICE_VERSION=$(VERSION) -t $(IMAGE):dev .

run: build ## Run the image locally (port set by PORT, default 8000)
	docker run --rm -p $(PORT):8000 --name $(IMAGE) $(IMAGE):dev

scan: build ## Fail on FIXABLE HIGH/CRITICAL vulnerabilities (unfixed ones are ignored; needs trivy)
	trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 $(IMAGE):dev
