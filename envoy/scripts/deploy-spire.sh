#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Installing standalone SPIRE..."

helm repo add spiffe https://spiffe.github.io/helm-charts-hardened 2>/dev/null || true
helm repo update spiffe

# Install SPIRE CRDs first
echo "Installing SPIRE CRDs..."
helm upgrade --install spire-crds spiffe/spire-crds \
    --version 0.5.0 \
    --namespace spire-system \
    --create-namespace \
    --wait

# Install SPIRE
echo "Installing SPIRE server and agents..."
helm upgrade --install spire spiffe/spire \
    --version 0.28.1 \
    --namespace spire-system \
    --values "${REPO_ROOT}/manifests/spire-values.yaml" \
    --wait --timeout 300s

echo "Waiting for SPIRE server..."
kubectl -n spire-system rollout status statefulset/spire-server --timeout=180s

echo "Waiting for SPIRE agents..."
kubectl -n spire-system rollout status daemonset/spire-agent --timeout=180s

echo "SPIRE installed"
kubectl -n spire-system get pods
