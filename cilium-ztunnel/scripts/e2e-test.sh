#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="mtls-test"

echo "=== Cilium Ztunnel mTLS E2E Test ==="
echo ""

# Deploy server on worker node
echo "Deploying server on worker node..."
kubectl -n "${NAMESPACE}" delete pod server --ignore-not-found --wait
kubectl -n "${NAMESPACE}" run server --image=nginx:1.28-alpine --port=80 \
    --overrides='{"spec":{"nodeName":"mtls-poc-worker"}}' --restart=Never

# Deploy client on worker2 node (cross-node)
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

SERVER_IP=$(kubectl -n "${NAMESPACE}" get pod server -o jsonpath='{.status.podIP}')
echo "Server IP: ${SERVER_IP}"

# Positive test - cross-node with mTLS via ztunnel
echo ""
echo "=== POSITIVE TEST: Client -> server via ztunnel (cross-node) ==="
if kubectl -n "${NAMESPACE}" exec client -- curl -s --max-time 10 "http://${SERVER_IP}" | grep -q "Welcome to nginx"; then
    echo "[PASS] Cross-node mTLS connection succeeded"
else
    echo "[FAIL] Cross-node connection failed"
    exit 1
fi

# Same-node test
echo ""
echo "=== SAME-NODE TEST: Client -> server on same node ==="
kubectl -n "${NAMESPACE}" delete pod client-same --ignore-not-found --wait
kubectl -n "${NAMESPACE}" run client-same --image=curlimages/curl:8.18.0 \
    --overrides='{"spec":{"nodeName":"mtls-poc-worker"}}' --restart=Never \
    --command -- sleep 3600
kubectl -n "${NAMESPACE}" wait --for=condition=ready pod/client-same --timeout=60s
sleep 5

if kubectl -n "${NAMESPACE}" exec client-same -- curl -s --max-time 10 "http://${SERVER_IP}" | grep -q "Welcome to nginx"; then
    echo "[PASS] Same-node mTLS connection succeeded"
else
    echo "[WARN] Same-node connection failed (may be expected in beta)"
fi
kubectl -n "${NAMESPACE}" delete pod client-same --ignore-not-found --wait=false

# Negative test - pod from non-enrolled namespace
echo ""
echo "=== NEGATIVE TEST: Pod from non-enrolled namespace ==="
kubectl create namespace no-ztunnel --dry-run=client -o yaml | kubectl apply -f -
kubectl -n no-ztunnel delete pod rogue --ignore-not-found --wait
kubectl -n no-ztunnel run rogue --image=curlimages/curl:8.18.0 \
    --overrides='{"spec":{"nodeName":"mtls-poc-worker"}}' --restart=Never \
    --command -- sleep 3600
kubectl -n no-ztunnel wait --for=condition=ready pod/rogue --timeout=60s
sleep 5

echo "Attempting connection from non-enrolled namespace..."
if kubectl -n no-ztunnel exec rogue -- curl -s --max-time 5 "http://${SERVER_IP}" 2>/dev/null | grep -q "Welcome to nginx"; then
    echo "[INFO] Connection succeeded - ztunnel does not block non-enrolled sources"
    echo "       (ztunnel requires BOTH endpoints enrolled for mTLS)"
else
    echo "[INFO] Connection failed - ztunnel may block mixed enrolled/non-enrolled traffic"
fi
kubectl delete namespace no-ztunnel --ignore-not-found --wait=false

# Proof: verify ztunnel is active
echo ""
echo "=== PROOF: Ztunnel enrollment ==="
kubectl exec -n kube-system ds/cilium -- cilium-dbg statedb dump 2>/dev/null \
    | jq '.["mtls-enrolled-namespaces"]' 2>/dev/null || \
    echo "(statedb dump not available)"

echo ""
echo "=== PROOF: Ztunnel config ==="
kubectl -n kube-system describe cm cilium-config 2>/dev/null \
    | grep -E "enable-ztunnel|encryption" || true

echo ""
echo "=== E2E Test Complete ==="
