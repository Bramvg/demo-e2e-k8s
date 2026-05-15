# Demo E2E on Kind with Argo CD

This repository now models an **ephemeral test environment** on a local **Kind** cluster with **Argo CD running inside the same cluster**.

## What it does

- boots a local Kind cluster
- installs Argo CD into that Kind cluster
- uses an **app-of-apps** setup to manage:
  - the Quarkus `greeting-app`
  - the Cucumber `e2e-tests`
- automatically syncs both child applications from Git
- runs the tests as an Argo CD hook after deployment
- tears the deployed app back down after the test run finishes

The important behavior is:

1. a Git change reaches the branch tracked by Argo CD
2. Argo CD syncs the root application
3. the greeting app is deployed
4. the Cucumber tests run
5. a cleanup hook deletes the greeting app resources again

That leaves the cluster ready for the next sync-triggered demo run.

## Repository layout

- `argocd/application.yaml` - bootstrap root application applied once to Argo CD
- `argocd/app-of-apps/` - Helm chart that renders the AppProject and the two child Argo CD applications
- `charts/greeting-app/` - Helm chart for the Quarkus demo app
- `charts/e2e-tests/` - Helm chart for the Cucumber test job and teardown hook
- `kind/kind-config.yaml` - Kind cluster configuration
- `scripts/bootstrap-kind-argocd.sh` - creates the cluster, installs Argo CD, builds and loads images, applies the root app
- `scripts/destroy-kind-cluster.sh` - removes the Kind cluster

## Prerequisites

Install these tools locally:

- `docker`
- `kind`
- `kubectl`
- `make`
- `mvn`
- `git`

Argo CD needs a Git repository it can reach. The bootstrap script reads:

- `remote.origin.url` as `REPO_URL`
- the current Git branch as `TARGET_REVISION`

You can override both with environment variables.

## One-command demo run

Use the top-level `Makefile` for the quickest demo flow:

```bash
make demo
```

Useful companion targets:

```bash
make status
make apps
make pods
make jobs
make ui
make password
make down
```

Show all available targets:

```bash
make help
```

## Bootstrap the demo manually

```bash
chmod +x scripts/bootstrap-kind-argocd.sh scripts/destroy-kind-cluster.sh
./scripts/bootstrap-kind-argocd.sh
```

If you need to override the repository URL or branch:

```bash
REPO_URL=https://github.com/<your-org>/demo-e2e-k8s.git \
TARGET_REVISION=main \
./scripts/bootstrap-kind-argocd.sh
```

The same overrides work with `make`:

```bash
REPO_URL=https://github.com/<your-org>/demo-e2e-k8s.git \
TARGET_REVISION=main \
make demo
```

## Watch the demo

```bash
kubectl get applications -n argocd
kubectl get pods -n demo-e2e -w
kubectl get jobs -n demo-e2e
```

Open the Argo CD UI locally:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Get the initial admin password:

```bash
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d
```

## Trigger another run

Push a new commit to the branch configured in the root application.

Because both child applications use automated sync, Argo CD will detect the Git change and start another deploy -> test -> teardown cycle.

## Tear everything down

```bash
make down
```

## Notes about teardown behavior

The teardown is intentionally done by an Argo CD hook job in `charts/e2e-tests/templates/cleanup-job.yaml`.

That job deletes the `greeting-app` Kubernetes resources after the tests complete. The Argo CD application definitions stay in place, so the next Git change can create the environment again.

## Local verification without Kind

You can still verify the application and tests locally:

```bash
mvn -f app/pom.xml -DskipTests package
java -jar app/target/quarkus-app/quarkus-run.jar
```

In another terminal:

```bash
APP_BASE_URL=http://localhost:8081 mvn -f tests/pom.xml test
```

Or with `make`:

```bash
make local-test
```

