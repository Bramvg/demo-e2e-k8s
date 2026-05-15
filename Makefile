SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

CLUSTER_NAME ?= demo-e2e
REPO_URL ?= $(shell git config --get remote.origin.url 2>/dev/null)
TARGET_REVISION ?= $(shell git rev-parse --abbrev-ref HEAD 2>/dev/null)
ARGOCD_NAMESPACE ?= argocd
DEMO_NAMESPACE ?= demo-e2e
APP_BASE_URL ?= http://localhost:8081

export CLUSTER_NAME REPO_URL TARGET_REVISION

.PHONY: help demo up down rebuild-images status watch ui password apps pods jobs local-app local-test verify

help: ## Show available make targets
	@awk 'BEGIN {FS = ":.*## "; printf "\nAvailable targets:\n\n"} /^[a-zA-Z0-9_.-]+:.*## / {printf "  %-16s %s\n", $$1, $$2} END {printf "\nOverrides: CLUSTER_NAME=..., REPO_URL=..., TARGET_REVISION=...\n\n"}' $(MAKEFILE_LIST)

demo: up ## One-command demo bootstrap on Kind

up: ## Create Kind, install Argo CD, build/load images, and bootstrap the app-of-apps
	./scripts/bootstrap-kind-argocd.sh

down: ## Delete the Kind cluster
	./scripts/destroy-kind-cluster.sh

rebuild-images: ## Re-run the full bootstrap flow to rebuild and reload the demo images
	./scripts/bootstrap-kind-argocd.sh

status: ## Show Argo CD apps and demo namespace resources
	kubectl get applications -n $(ARGOCD_NAMESPACE)
	@printf '\n'
	kubectl get all -n $(DEMO_NAMESPACE)

watch: ## Watch pods in the demo namespace
	kubectl get pods -n $(DEMO_NAMESPACE) -w

ui: ## Port-forward the Argo CD UI to https://localhost:8080
	kubectl port-forward svc/argocd-server -n $(ARGOCD_NAMESPACE) 8080:443

password: ## Print the initial Argo CD admin password
	kubectl get secret argocd-initial-admin-secret -n $(ARGOCD_NAMESPACE) -o jsonpath='{.data.password}' | base64 -d && printf '\n'

apps: ## List Argo CD applications
	kubectl get applications -n $(ARGOCD_NAMESPACE)

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

