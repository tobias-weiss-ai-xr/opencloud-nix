# SPDX-FileCopyrightText: 2026 opencloud-nix Contributors
# SPDX-License-Identifier: Apache-2.0
#
# opencloud-nix — Development Makefile
#
# Shares a single ./.env for secrets across the docker compose and helmfile
# deployment flows.

SHELL := /bin/bash

CHART := helmfile/charts/opencloud
REGISTRY ?= ghcr.io/tobias-weiss-ai-xr
TAG ?= 9.1.0

# ---------------------------------------------------------------------------
# Container image (Nix-built)
# ---------------------------------------------------------------------------
image: ## Build the OpenCloud image with Nix (nix/images/opencloud)
	cd nix/images/opencloud && nix build .#opencloud --print-build-logs

image-load: image ## Build and load the image into docker (for compose)
	docker load < nix/images/opencloud/result
	@echo "Loaded image. For compose, set OPENCLOUD_IMAGE=opencloud:$(TAG) in .env"

image-push: image ## Push the Nix image to $(REGISTRY) (skopeo)
	skopeo copy docker-archive:nix/images/opencloud/result docker://$(REGISTRY)/opencloud:$(TAG)

# ---------------------------------------------------------------------------
# Docker Compose deployment (localhost:9200)
# ---------------------------------------------------------------------------
compose-setup: ## Create .env from .env.example and fill in random secrets
	@test -f .env || cp .env.example .env
	@for v in OPENCLOUD_JWT_SECRET OPENCLOUD_TRANSFER_SECRET OPENCLOUD_MACHINE_AUTH_API_KEY OPENCLOUD_SYSTEM_USER_API_KEY OPENCLOUD_URL_SIGNING_SECRET; do \
		if grep -q "^$$v=$$" .env; then \
			sed -i "s|^$$v=.*|$$v=$$(openssl rand -hex 32)|" .env; \
			echo "  generated $$v"; \
		fi; \
	done
	@mkdir -p data
	@if [ -n "$$(id -u 2>/dev/null)" ] && [ "$$(id -u)" = "0" ]; then \
		chown -R 1000:1000 data; \
	else \
		sudo chown -R 1000:1000 data 2>/dev/null || echo "  NOTE: chown data/ to uid 1000:1000 before running as the non-root OpenCloud user (or sudo make compose-setup)"; \
	fi
	@echo "==> .env ready. Start with: make compose-up"

compose-up: compose-setup ## Start OpenCloud via docker compose
	docker compose up -d
	@echo "==> OpenCloud on $$(grep '^OPENCLOUD_URL=' .env | cut -d= -f2)"

compose-down: ## Stop docker compose services
	docker compose down

compose-logs: ## Tail docker compose logs
	docker compose logs -f

compose-ps: ## docker compose ps
	docker compose ps

# ---------------------------------------------------------------------------
# Helmfile deployment (kubernetes)
# ---------------------------------------------------------------------------
.PHONY: helmfile-apply helmfile-diff helmfile-template helmfile-sync

# `.env` seeds the helmfile environment (OPENCLOUD_* env vars, see
# helmfile/releases/opencloud/values.yaml.gotmpl).
HELMFILE_RUN := set -a; . ../.env; set +a; helmfile -e default -f helmfile.yaml

helmfile-apply: compose-setup ## Deploy OpenCloud via helmfile (sync)
	cd helmfile && $(HELMFILE_RUN) sync

helmfile-sync: helmfile-apply ## Alias for helmfile-apply

helmfile-diff: compose-setup ## Dry-run: show helmfile changes
	cd helmfile && $(HELMFILE_RUN) diff

helmfile-template: compose-setup ## Render helmfile-generated values/manifests
	cd helmfile && $(HELMFILE_RUN) template

# ---------------------------------------------------------------------------
# Chart validation
# ---------------------------------------------------------------------------
lint: ## Run helm lint on the OpenCloud chart
	helm lint $(CHART)

template: ## Render the chart with CI values via helm template
	helm template opencloud $(CHART) --values $(CHART)/ci/ci-values.yaml > /dev/null

unittest: ## Run helm-unittest suites in $(CHART)/tests
	@if ! helm plugin list 2>/dev/null | grep -q unittest; then \
		echo "Installing helm-unittest plugin..."; \
		helm plugin install https://github.com/helm-unittest/helm-unittest.git --version v0.7.2; \
	fi
	helm unittest $(CHART)

test: lint template unittest ## Run all chart tests (lint + template + unittest)

# Plain-YAML files only: Go-templated chart templates (templates/*.yaml),
# helmfile .gotmpl files, .env and Nix sources are not YAML and are excluded.
YAMLLINT_FILES := \
	helmfile/helmfile.yaml \
	helmfile/environments/default/values.yaml \
	helmfile/charts/opencloud/Chart.yaml \
	helmfile/charts/opencloud/values.yaml \
	helmfile/charts/opencloud/ci/ci-values.yaml \
	compose.yaml \
	config/opencloud.yaml

yamllint: ## Run yamllint on plain-YAML files
	@yamllint -c .yamllint $(YAMLLINT_FILES)

spellcheck: ## Run cspell on documentation
	@cspell --config cspell.json README.md helmfile/ --no-progress

# ---------------------------------------------------------------------------
clean: ## Remove build artifacts
	@rm -rf nix/images/opencloud/result
	@echo "==> Cleaned."
