#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Deploying per-node Envoy proxy..."

# Create namespace
kubectl create namespace envoy-system --dry-run=client -o yaml | kubectl apply -f -

# Create ClusterSPIFFEID for Envoy proxy
echo "Creating ClusterSPIFFEID for workloads..."
kubectl apply -f - <<EOF
apiVersion: spire.spiffe.io/v1alpha1
kind: ClusterSPIFFEID
metadata:
  name: envoy-proxy
spec:
  spiffeIDTemplate: "spiffe://prod.metal3.local/ns/{{ .PodMeta.Namespace }}/sa/{{ .PodSpec.ServiceAccountName }}"
  podSelector: {}
  namespaceSelector:
    matchExpressions:
    - key: kubernetes.io/metadata.name
      operator: NotIn
      values:
      - kube-system
      - kube-node-lease
      - kube-public
      - spire-system
      - envoy-system
  ttl: 1h
EOF

# Deploy Envoy ConfigMap
echo "Creating Envoy configuration..."
kubectl apply -f "${REPO_ROOT}/manifests/envoy-config.yaml"

# Deploy Envoy DaemonSet
echo "Deploying Envoy DaemonSet..."
kubectl apply -f "${REPO_ROOT}/manifests/envoy-daemonset.yaml"

echo "Waiting for Envoy pods..."
kubectl -n envoy-system rollout status daemonset/envoy-proxy --timeout=180s

echo "Envoy per-node proxy deployed"
kubectl -n envoy-system get pods -o wide
