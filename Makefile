SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

CLUSTER_NAME ?= demo-e2e
REPO_URL ?= $(shell git config --get remote.origin.url 2>/dev/null)
TARGET_REVISION ?= $(shell git rev-parse --abbrev-ref HEAD 2>/dev/null)
ARGOCD_NAMESPACE ?= argocd
DEMO_NAMESPACE ?= demo-e2e
APP_BASE_URL ?= http://localhost:8081
KIND_CONTEXT ?= kind-$(CLUSTER_NAME)
TRIGGER_MESSAGE ?= chore: trigger demo rerun
WATCH_INTERVAL ?= 5

# Use the Kind context automatically for selected read/UI targets when available.
KUBECTL_CONTEXT_ARG :=
ifneq ($(shell command -v kubectl >/dev/null 2>&1 && kubectl config get-contexts "$(KIND_CONTEXT)" >/dev/null 2>&1 && echo yes),)
KUBECTL_CONTEXT_ARG := --context $(KIND_CONTEXT)
endif

export CLUSTER_NAME REPO_URL TARGET_REVISION

.PHONY: help doctor demo up rerun trigger down rebuild-images status watch watch-run ui password apps pods jobs local-app local-test verify

help: ## Show available make targets
	@awk 'BEGIN {FS = ":.*## "; printf "\nAvailable targets:\n\n"} /^[a-zA-Z0-9_.-]+:.*## / {printf "  %-16s %s\n", $$1, $$2} END {printf "\nOverrides: CLUSTER_NAME=..., REPO_URL=..., TARGET_REVISION=...\n\n"}' $(MAKEFILE_LIST)

doctor: ## Run preflight checks for tools, Docker, and kubectl/Kind context
	@set -euo pipefail; \
	for cmd in kind kubectl docker mvn git; do \
	  command -v "$$cmd" >/dev/null 2>&1 || { echo "Missing required command: $$cmd" >&2; exit 1; }; \
	done; \
	docker info >/dev/null 2>&1 || { echo "Docker daemon is not reachable. Start Docker and retry." >&2; exit 1; }; \
	echo "Current kubectl context: $$(kubectl config current-context 2>/dev/null || echo none)"; \
	kind_context="kind-$(CLUSTER_NAME)"; \
	if kind get clusters | grep -qx "$(CLUSTER_NAME)"; then \
	  kubectl config get-contexts "$$kind_context" >/dev/null 2>&1 || { echo "Kind cluster exists but kubectl context '$$kind_context' is missing." >&2; exit 1; }; \
	  kubectl cluster-info --context "$$kind_context" >/dev/null 2>&1 || { echo "Kind context '$$kind_context' is not reachable." >&2; exit 1; }; \
	  if [[ "$$(kubectl config current-context 2>/dev/null || true)" != "$$kind_context" ]]; then \
	    echo "Warning: current context is not '$$kind_context'."; \
	    echo "Run: kubectl config use-context $$kind_context"; \
	  fi; \
	fi; \
	echo "Doctor checks passed."

demo: doctor up ## One-command demo bootstrap on Kind

up: ## Create Kind, install Argo CD, build/load images, and bootstrap the app-of-apps
	./scripts/bootstrap-kind-argocd.sh

rerun: ## Force a hard refresh of the root Argo CD app after pushing a new commit
	kubectl $(KUBECTL_CONTEXT_ARG) annotate application demo-e2e -n $(ARGOCD_NAMESPACE) argocd.argoproj.io/refresh=hard --overwrite
	@printf '\nApplications:\n'
	kubectl $(KUBECTL_CONTEXT_ARG) get applications -n $(ARGOCD_NAMESPACE)
	@printf '\nJobs:\n'
	kubectl $(KUBECTL_CONTEXT_ARG) get jobs -n $(DEMO_NAMESPACE)

trigger: ## Create an empty commit, push the current branch, then refresh Argo CD
	@test "$$(git rev-parse --abbrev-ref HEAD)" != "HEAD" || (echo "Detached HEAD detected. Check out a branch before running make trigger." >&2; exit 1)
	@git remote get-url origin >/dev/null 2>&1 || (echo "Git remote 'origin' is not configured." >&2; exit 1)
	@echo "Creating empty commit on '$$(git rev-parse --abbrev-ref HEAD)'"
	git commit --allow-empty -m "$(TRIGGER_MESSAGE)"
	@echo "Pushing '$$(git rev-parse --abbrev-ref HEAD)' to origin"
	git push origin "$$(git rev-parse --abbrev-ref HEAD)"
	+$(MAKE) rerun

down: ## Delete the Kind cluster
	./scripts/destroy-kind-cluster.sh

rebuild-images: ## Re-run the full bootstrap flow to rebuild and reload the demo images
	./scripts/bootstrap-kind-argocd.sh

status: ## Show Argo CD apps and demo namespace resources
	kubectl $(KUBECTL_CONTEXT_ARG) get applications -n $(ARGOCD_NAMESPACE)
	@printf '\n'
	kubectl $(KUBECTL_CONTEXT_ARG) get all -n $(DEMO_NAMESPACE)

watch: ## Watch pods in the demo namespace
	kubectl get pods -n $(DEMO_NAMESPACE) -w

watch-run: ## Continuously show apps, jobs, and pods for the current demo run
	@bash -c 'set -euo pipefail; trap "exit 0" INT TERM; while true; do clear >/dev/null 2>&1 || printf "\033[2J\033[H"; echo "Demo run watcher - $$(date)"; echo; echo "Applications:"; kubectl $(KUBECTL_CONTEXT_ARG) get applications -n $(ARGOCD_NAMESPACE); echo; echo "Jobs:"; kubectl $(KUBECTL_CONTEXT_ARG) get jobs -n $(DEMO_NAMESPACE); echo; echo "Pods:"; kubectl $(KUBECTL_CONTEXT_ARG) get pods -n $(DEMO_NAMESPACE); sleep $(WATCH_INTERVAL); done'

ui: ## Port-forward the Argo CD UI to https://localhost:8080
	kubectl $(KUBECTL_CONTEXT_ARG) port-forward svc/argocd-server -n $(ARGOCD_NAMESPACE) 8080:443

password: ## Print the initial Argo CD admin password
	kubectl get secret argocd-initial-admin-secret -n $(ARGOCD_NAMESPACE) -o jsonpath='{.data.password}' | base64 -d && printf '\n'

apps: ## List Argo CD applications
	kubectl $(KUBECTL_CONTEXT_ARG) get applications -n $(ARGOCD_NAMESPACE)

pods: ## List pods in the demo namespace
	kubectl get pods -n $(DEMO_NAMESPACE)

jobs: ## List jobs in the demo namespace
	kubectl get jobs -n $(DEMO_NAMESPACE)

local-app: ## Run the Quarkus app locally after packaging it
	mvn -f app/pom.xml -DskipTests package
	java -jar app/target/quarkus-app/quarkus-run.jar

local-test: ## Run the Cucumber tests against APP_BASE_URL
	APP_BASE_URL=$(APP_BASE_URL) mvn -f tests/pom.xml test

verify: ## Run the local build, test, and Helm lint checks
	mvn -f app/pom.xml -DskipTests package
	bash -c 'set -euo pipefail; java -jar app/target/quarkus-app/quarkus-run.jar >/tmp/demo-e2e-app.log 2>&1 & app_pid=$$!; trap "kill $$app_pid" EXIT; for attempt in $$(seq 1 30); do if curl --fail --silent $(APP_BASE_URL)/hello >/dev/null; then break; fi; sleep 1; done; APP_BASE_URL=$(APP_BASE_URL) mvn -f tests/pom.xml test'
	helm lint charts/greeting-app
	helm lint charts/e2e-tests
	helm lint argocd/app-of-apps

