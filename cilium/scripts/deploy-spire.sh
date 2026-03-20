#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Adding SPIFFE Helm repo..."
helm repo add spiffe https://spiffe.github.io/helm-charts-hardened
helm repo update spiffe

echo "Creating spire-system namespace..."
kubectl create namespace spire-system --dry-run=client -o yaml | kubectl apply -f -

echo "Installing SPIRE CRDs..."
helm upgrade --install spire-crds spiffe/spire-crds \
    --version 0.5.0 \
    --namespace spire-system \
    --wait --timeout 2m

echo "Deploying SPIRE..."
helm upgrade --install spire spiffe/spire \
    --version 0.28.1 \
    --namespace spire-system \
    -f "${REPO_ROOT}/manifests/spire-values.yaml" \
    --wait --timeout 5m

echo "Waiting for SPIRE server..."
kubectl -n spire-system wait --for=condition=ready pod \
    -l app.kubernetes.io/name=server --timeout=180s

echo "Waiting for SPIRE agents..."
kubectl -n spire-system wait --for=condition=ready pod \
    -l app.kubernetes.io/name=agent --timeout=180s

echo "SPIRE deployment complete"
kubectl -n spire-system get pods
