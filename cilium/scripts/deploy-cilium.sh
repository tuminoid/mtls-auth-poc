#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Adding Cilium Helm repo..."
helm repo add cilium https://helm.cilium.io/
helm repo update cilium

echo "Deploying Cilium with WireGuard encryption..."
helm upgrade --install cilium cilium/cilium \
    --version 1.19.0 \
    --namespace kube-system \
    -f "${REPO_ROOT}/manifests/cilium-values.yaml" \
    --wait --timeout 5m

echo "Waiting for Cilium pods..."
kubectl -n kube-system wait --for=condition=ready pod \
    -l k8s-app=cilium --timeout=180s

echo "Cilium deployment complete"
kubectl -n kube-system get pods -l k8s-app=cilium
