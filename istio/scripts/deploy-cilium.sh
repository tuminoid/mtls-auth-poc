#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Installing Cilium with Istio compatibility..."

helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
helm repo update cilium

# Get API server endpoint for Kind (avoids service IP bootstrap issue)
API_SERVER_IP=$(kubectl get endpoints kubernetes -o jsonpath='{.subsets[0].addresses[0].ip}')
API_SERVER_PORT=$(kubectl get endpoints kubernetes -o jsonpath='{.subsets[0].ports[0].port}')

helm install cilium cilium/cilium \
    --version 1.19.0 \
    --namespace kube-system \
    --values "${REPO_ROOT}/manifests/cilium-values.yaml" \
    --set k8sServiceHost="${API_SERVER_IP}" \
    --set k8sServicePort="${API_SERVER_PORT}" \
    --wait --timeout 300s

echo "Waiting for Cilium to be ready..."
kubectl -n kube-system rollout status daemonset/cilium --timeout=300s

echo "Cilium installed with Istio compatibility"
kubectl -n kube-system get pods -l k8s-app=cilium
