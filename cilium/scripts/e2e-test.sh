#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="mtls-test"

echo "=== mTLS E2E Test ==="
echo ""

# Setup
echo "Setting up test namespace..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "Applying CiliumNetworkPolicy requiring authentication from same namespace..."
kubectl apply -f - <<EOF
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: require-auth
  namespace: ${NAMESPACE}
spec:
  endpointSelector: {}
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: ${NAMESPACE}
      authentication:
        mode: required
EOF

echo "Deploying server on worker node..."
kubectl -n "${NAMESPACE}" delete pod server --ignore-not-found --wait
kubectl -n "${NAMESPACE}" run server --image=nginx:1.28-alpine --port=80 \
    --overrides='{"spec":{"nodeName":"mtls-poc-worker"}}' --restart=Never

echo "Deploying client on worker2 node (cross-node)..."
kubectl -n "${NAMESPACE}" delete pod client --ignore-not-found --wait
kubectl -n "${NAMESPACE}" run client --image=curlimages/curl:8.18.0 \
    --overrides='{"spec":{"nodeName":"mtls-poc-worker2"}}' --restart=Never \
    --command -- sleep 3600

echo "Waiting for pods..."
kubectl -n "${NAMESPACE}" wait --for=condition=ready pod/server --timeout=60s
kubectl -n "${NAMESPACE}" wait --for=condition=ready pod/client --timeout=60s

SERVER_IP=$(kubectl -n "${NAMESPACE}" get pod server -o jsonpath='{.status.podIP}')
echo "Server IP: ${SERVER_IP}"

echo "Waiting for SPIFFE identities (15s)..."
sleep 15

# Positive test - cross-node with mTLS
echo ""
echo "=== POSITIVE TEST: Authenticated client -> server (cross-node) ==="
if kubectl -n "${NAMESPACE}" exec client -- curl -s --max-time 10 "http://${SERVER_IP}" | grep -q "Welcome to nginx"; then
    echo "[PASS] Cross-node authenticated connection succeeded"
else
    echo "[FAIL] Cross-node authenticated connection failed"
    exit 1
fi

# Negative test - rogue pod on SAME node (tests identity-based policy without mTLS handshake)
echo ""
echo "=== NEGATIVE TEST: Rogue pod from different namespace (same node) ==="
kubectl create namespace rogue-ns --dry-run=client -o yaml | kubectl apply -f -
kubectl -n rogue-ns delete pod rogue --ignore-not-found --wait
kubectl -n rogue-ns run rogue --image=curlimages/curl:8.18.0 \
    --overrides='{"spec":{"nodeName":"mtls-poc-worker"}}' --restart=Never \
    --command -- sleep 3600
kubectl -n rogue-ns wait --for=condition=ready pod/rogue --timeout=60s
sleep 5

echo "Attempting connection from rogue namespace..."
if kubectl -n rogue-ns exec rogue -- curl -s --max-time 5 "http://${SERVER_IP}" 2>/dev/null | grep -q "Welcome to nginx"; then
    echo "[FAIL] Connection succeeded - policy should block cross-namespace traffic"
    kubectl delete namespace rogue-ns --ignore-not-found --wait=false
    exit 1
else
    echo "[PASS] Connection blocked - identity policy enforced on same node"
fi
kubectl delete namespace rogue-ns --ignore-not-found --wait=false

echo ""
echo "=== PROOF: Policy with authentication mode ==="
kubectl -n kube-system exec ds/cilium -- cilium policy get 2>/dev/null | grep -A5 '"authentication"' | head -6 || true

echo ""
echo "=== PROOF: SPIRE integration active ==="
kubectl -n kube-system logs ds/cilium 2>/dev/null | grep "Spire Delegate API Client is running" | tail -1 || true

echo ""
echo "=== E2E Test Complete ==="
