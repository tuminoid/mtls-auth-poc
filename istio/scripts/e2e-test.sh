#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="mtls-test"

echo "=== Istio Ambient mTLS E2E Test ==="
echo ""

# Setup namespace with ambient mode
echo "Setting up test namespace with ambient mode..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "${NAMESPACE}" istio.io/dataplane-mode=ambient --overwrite

# Apply STRICT mTLS policy to block non-mesh traffic
echo "Applying PeerAuthentication STRICT mode..."
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: strict-mtls
  namespace: ${NAMESPACE}
spec:
  mtls:
    mode: STRICT
EOF

echo "Deploying server on worker node..."
kubectl -n "${NAMESPACE}" delete pod server --ignore-not-found --wait
kubectl -n "${NAMESPACE}" run server --image=nginx:1.28-alpine --port=80 \
    --overrides='{"spec":{"nodeName":"mtls-poc-worker"}}' --restart=Never
kubectl -n "${NAMESPACE}" delete svc server --ignore-not-found
kubectl -n "${NAMESPACE}" expose pod server --port=80

echo "Deploying client on worker2 node (cross-node)..."
kubectl -n "${NAMESPACE}" delete pod client --ignore-not-found --wait
kubectl -n "${NAMESPACE}" run client --image=curlimages/curl:8.18.0 \
    --overrides='{"spec":{"nodeName":"mtls-poc-worker2"}}' --restart=Never \
    --command -- sleep 3600

echo "Waiting for pods..."
kubectl -n "${NAMESPACE}" wait --for=condition=ready pod/server --timeout=60s
kubectl -n "${NAMESPACE}" wait --for=condition=ready pod/client --timeout=60s

echo "Waiting for ztunnel enrollment (10s)..."
sleep 10

# Positive test - cross-node with mTLS via ztunnel
echo ""
echo "=== POSITIVE TEST: Client -> server via ztunnel (cross-node) ==="
if kubectl -n "${NAMESPACE}" exec client -- curl -s --max-time 10 http://server | grep -q "Welcome to nginx"; then
    echo "[PASS] Cross-node authenticated connection succeeded"
else
    echo "[FAIL] Cross-node connection failed"
    exit 1
fi

# Negative test - pod in non-ambient namespace (should be blocked by STRICT mTLS)
echo ""
echo "=== NEGATIVE TEST: Pod from non-ambient namespace (STRICT mTLS) ==="
kubectl create namespace no-ambient --dry-run=client -o yaml | kubectl apply -f -
kubectl -n no-ambient delete pod rogue --ignore-not-found --wait
kubectl -n no-ambient run rogue --image=curlimages/curl:8.18.0 \
    --overrides='{"spec":{"nodeName":"mtls-poc-worker"}}' --restart=Never \
    --command -- sleep 3600
kubectl -n no-ambient wait --for=condition=ready pod/rogue --timeout=60s
sleep 5

SERVER_IP=$(kubectl -n "${NAMESPACE}" get pod server -o jsonpath='{.status.podIP}')
echo "Attempting plaintext connection from non-mesh pod to ${SERVER_IP}..."
if kubectl -n no-ambient exec rogue -- curl -s --max-time 5 "http://${SERVER_IP}" 2>/dev/null | grep -q "Welcome to nginx"; then
    echo "[FAIL] Connection succeeded - STRICT mTLS should have blocked plaintext"
    kubectl delete namespace no-ambient --ignore-not-found --wait=false
    exit 1
else
    echo "[PASS] Connection blocked - STRICT mTLS enforced"
fi
kubectl delete namespace no-ambient --ignore-not-found --wait=false

echo ""
echo "=== PROOF: PeerAuthentication policy ==="
kubectl -n "${NAMESPACE}" get peerauthentication strict-mtls -o yaml | grep -A3 "spec:"

echo ""
echo "=== E2E Test Complete ==="
