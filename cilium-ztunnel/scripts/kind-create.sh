#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-mtls-poc}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Creating Kind cluster: ${CLUSTER_NAME}"
kind create cluster --name "${CLUSTER_NAME}" --config "${REPO_ROOT}/manifests/kind-config.yaml"

echo "Kind cluster ${CLUSTER_NAME} created (CNI not installed yet)"
kubectl get nodes
