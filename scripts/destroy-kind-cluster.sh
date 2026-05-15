#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-demo-e2e}"

kind delete cluster --name "${CLUSTER_NAME}"

