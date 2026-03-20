#!/usr/bin/env bash
set -euo pipefail

ISTIO_VERSION="${ISTIO_VERSION:-1.28.3}"

echo "Installing Istio Ambient ${ISTIO_VERSION}..."

helm repo add istio https://istio-release.storage.googleapis.com/charts 2>/dev/null || true
helm repo update istio

# Install base
echo "Installing istio-base..."
helm install istio-base istio/base \
    -n istio-system \
    --version "${ISTIO_VERSION}" \
    --create-namespace \
    --wait

# Install Gateway API CRDs
echo "Installing Gateway API CRDs..."
kubectl apply --server-side -f \
    https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml

# Install istiod with ambient profile
echo "Installing istiod..."
helm install istiod istio/istiod \
    -n istio-system \
    --version "${ISTIO_VERSION}" \
    --set profile=ambient \
    --wait

# Install CNI
echo "Installing istio-cni..."
helm install istio-cni istio/cni \
    -n istio-system \
    --version "${ISTIO_VERSION}" \
    --set profile=ambient \
    --wait

# Install ztunnel
echo "Installing ztunnel..."
helm install ztunnel istio/ztunnel \
    -n istio-system \
    --version "${ISTIO_VERSION}" \
    --wait

echo "Waiting for ztunnel to be ready..."
kubectl -n istio-system rollout status daemonset/ztunnel --timeout=300s

echo "Istio Ambient ${ISTIO_VERSION} installed"
kubectl -n istio-system get pods
