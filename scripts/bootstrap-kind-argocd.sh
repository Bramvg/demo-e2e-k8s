#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-demo-e2e}"
KIND_CONFIG="${KIND_CONFIG:-${ROOT_DIR}/kind/kind-config.yaml}"
ARGOCD_VERSION="${ARGOCD_VERSION:-stable}"
REPO_URL="${REPO_URL:-$(git -C "${ROOT_DIR}" config --get remote.origin.url || true)}"
TARGET_REVISION="${TARGET_REVISION:-$(git -C "${ROOT_DIR}" rev-parse --abbrev-ref HEAD)}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

for command_name in kind kubectl docker mvn git; do
  require_command "${command_name}"
done

if [[ -z "${REPO_URL}" ]]; then
  echo "Set REPO_URL or configure git remote.origin.url before bootstrapping Argo CD." >&2
  exit 1
fi

if [[ "${TARGET_REVISION}" == "HEAD" ]]; then
  echo "Set TARGET_REVISION explicitly when working from a detached HEAD." >&2
  exit 1
fi

echo "Creating Kind cluster '${CLUSTER_NAME}'"
if ! kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  kind create cluster --name "${CLUSTER_NAME}" --config "${KIND_CONFIG}"
else
  echo "Kind cluster '${CLUSTER_NAME}' already exists, reusing it"
fi

echo "Building the greeting app"
mvn -f "${ROOT_DIR}/app/pom.xml" -DskipTests package

echo "Building the greeting app image"
docker build -t greeting-app:latest -f "${ROOT_DIR}/app/src/main/docker/Dockerfile.jvm" "${ROOT_DIR}/app"

echo "Building the Cucumber test image"
docker build -t e2e-cucumber-tests:latest "${ROOT_DIR}/tests"

echo "Loading images into Kind"
kind load docker-image --name "${CLUSTER_NAME}" greeting-app:latest
kind load docker-image --name "${CLUSTER_NAME}" e2e-cucumber-tests:latest

echo "Installing Argo CD into the cluster"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=300s

for deployment_name in argocd-applicationset-controller argocd-dex-server argocd-notifications-controller argocd-redis argocd-repo-server argocd-server; do
  if kubectl get deployment/"${deployment_name}" -n argocd >/dev/null 2>&1; then
    kubectl rollout status deployment/"${deployment_name}" -n argocd --timeout=300s
  fi
done

echo "Applying the root Argo CD application"
sed \
  -e "s#__REPO_URL__#${REPO_URL}#g" \
  -e "s#__TARGET_REVISION__#${TARGET_REVISION}#g" \
  "${ROOT_DIR}/argocd/application.yaml" | kubectl apply -f -

echo
echo "Bootstrap complete. Helpful follow-up commands:"
echo "  kubectl get applications -n argocd"
echo "  kubectl get pods -n demo-e2e"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"

