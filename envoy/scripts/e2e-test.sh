#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="mtls-test"

echo "=== Envoy Per-Node mTLS E2E Test ==="
echo ""
echo "NOTE: This POC demonstrates that node-level iptables CANNOT intercept"
echo "pod-to-pod traffic. Pods have isolated network namespaces, so node-level"
echo "REDIRECT rules only see host-network traffic."
echo ""

# Setup namespace
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# Deploy server on worker node
echo "Deploying server on worker node..."
kubectl -n "${NAMESPACE}" delete pod server --ignore-not-found --wait
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: server
  namespace: ${NAMESPACE}
---
apiVersion: v1
kind: Pod
metadata:
  name: server
  namespace: ${NAMESPACE}
  labels:
    app: server
spec:
  serviceAccountName: server
  nodeName: mtls-poc-worker
  containers:
  - name: nginx
    image: nginx:1.28-alpine
    ports:
    - containerPort: 80
EOF

# Deploy client on worker2 node
echo "Deploying client on worker2 node..."
kubectl -n "${NAMESPACE}" delete pod client --ignore-not-found --wait
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: client
  namespace: ${NAMESPACE}
---
apiVersion: v1
kind: Pod
metadata:
  name: client
  namespace: ${NAMESPACE}
  labels:
    app: client
spec:
  serviceAccountName: client
  nodeName: mtls-poc-worker2
  containers:
  - name: curl
    image: curlimages/curl:8.18.0
    command: ["sleep", "3600"]
EOF

echo "Waiting for pods..."
kubectl -n "${NAMESPACE}" wait --for=condition=ready pod/server --timeout=60s
kubectl -n "${NAMESPACE}" wait --for=condition=ready pod/client --timeout=60s

SERVER_IP=$(kubectl -n "${NAMESPACE}" get pod server -o jsonpath='{.status.podIP}')
echo "Server IP: ${SERVER_IP}"

# Wait for SPIRE identities
echo "Waiting for SPIFFE identities (15s)..."
sleep 15

echo ""
echo "=== SPIRE entries ==="
kubectl -n spire-system exec spire-server-0 -c spire-server -- \
    /opt/spire/bin/spire-server entry show 2>/dev/null | grep -A2 "${NAMESPACE}" || echo "Entries pending..."

# Test 1: Direct connection works (traffic bypasses Envoy)
echo ""
echo "=== TEST 1: Direct pod-to-pod connection ==="
if kubectl -n "${NAMESPACE}" exec client -- curl -s --max-time 10 "http://${SERVER_IP}" | grep -q "Welcome to nginx"; then
    echo "[PASS] Connection succeeded (but NOT through Envoy - see below)"
else
    echo "[FAIL] Connection failed"
    exit 1
fi

# Test 2: Verify traffic did NOT go through Envoy
echo ""
echo "=== TEST 2: Verify iptables interception (expected: 0 packets) ==="
WORKER_PKTS=$(docker exec mtls-poc-worker iptables -t nat -L ENVOY_OUT -n -v 2>/dev/null | grep REDIRECT | awk '{print $1}')
WORKER2_PKTS=$(docker exec mtls-poc-worker2 iptables -t nat -L ENVOY_OUT -n -v 2>/dev/null | grep REDIRECT | awk '{print $1}')
echo "Packets redirected on worker: ${WORKER_PKTS:-0}"
echo "Packets redirected on worker2: ${WORKER2_PKTS:-0}"

if [[ "${WORKER_PKTS:-0}" == "0" ]] && [[ "${WORKER2_PKTS:-0}" == "0" ]]; then
    echo "[EXPECTED] No packets intercepted - node-level iptables cannot see pod traffic"
else
    echo "[UNEXPECTED] Some packets were intercepted"
fi

echo ""
echo "=== CONCLUSION ==="
echo "Node-level iptables interception does NOT work for pod-to-pod traffic."
echo "Transparent mTLS requires one of:"
echo "  1. Per-pod init containers (istio-init) - iptables in pod netns"
echo "  2. CNI plugin (istio-cni) - inject rules when pod starts"
echo "  3. eBPF (Cilium) - kernel-level interception"
echo ""
echo "=== E2E Test Complete ==="
