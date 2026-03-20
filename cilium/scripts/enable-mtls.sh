#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Upgrading Cilium with built-in SPIRE and mutual authentication..."
helm upgrade cilium cilium/cilium \
    --version 1.19.0 \
    --namespace kube-system \
    -f "${REPO_ROOT}/manifests/cilium-mtls-values.yaml" \
    --wait --timeout 10m

echo "Waiting for Cilium pods..."
kubectl -n kube-system rollout status daemonset/cilium --timeout=300s

echo "Waiting for Cilium SPIRE server..."
kubectl -n cilium-spire wait --for=condition=ready pod -l app=spire-server --timeout=180s

echo "Waiting for Cilium SPIRE agents..."
kubectl -n cilium-spire wait --for=condition=ready pod -l app=spire-agent --timeout=180s

echo "Restarting Cilium to ensure SPIRE socket connectivity..."
kubectl -n kube-system rollout restart ds/cilium
kubectl -n kube-system rollout status daemonset/cilium --timeout=180s

echo "Cilium mutual authentication with built-in SPIRE enabled"
