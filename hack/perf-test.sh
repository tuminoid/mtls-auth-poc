#!/usr/bin/env bash
set -euo pipefail

# Shared performance test - deploys pods in mtls-test namespace
# with cross-node placement and runs iperf3 + fortio benchmarks.

NAMESPACE="mtls-test"

echo "=== Performance Test ==="
echo ""

# Get worker nodes
SERVER_NODE=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}')
CLIENT_NODE=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[1].metadata.name}')
echo "Server node: ${SERVER_NODE}"
echo "Client node: ${CLIENT_NODE}"

# Clean up any existing pods
kubectl -n "${NAMESPACE}" delete pod iperf-server fortio-server iperf-client fortio-client --ignore-not-found --wait 2>/dev/null || true

# Deploy pods with explicit node placement
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: iperf-server
  namespace: ${NAMESPACE}
spec:
  nodeName: ${SERVER_NODE}
  containers:
  - name: iperf
    image: networkstatic/iperf3:latest
    args: ["-s"]
---
apiVersion: v1
kind: Pod
metadata:
  name: fortio-server
  namespace: ${NAMESPACE}
spec:
  nodeName: ${SERVER_NODE}
  containers:
  - name: fortio
    image: fortio/fortio:1.73.2
    args: ["server"]
---
apiVersion: v1
kind: Pod
metadata:
  name: iperf-client
  namespace: ${NAMESPACE}
spec:
  nodeName: ${CLIENT_NODE}
  containers:
  - name: iperf
    image: networkstatic/iperf3:latest
    command: ["sleep", "infinity"]
---
apiVersion: v1
kind: Pod
metadata:
  name: fortio-client
  namespace: ${NAMESPACE}
spec:
  nodeName: ${CLIENT_NODE}
  containers:
  - name: fortio
    image: fortio/fortio:1.73.2
    args: ["server", "-http-port", "0", "-grpc-port", "0"]
EOF

echo "Waiting for pods..."
kubectl -n "${NAMESPACE}" wait --for=condition=Ready \
    pod/iperf-server pod/fortio-server pod/iperf-client pod/fortio-client \
    --timeout=120s

IPERF_IP=$(kubectl -n "${NAMESPACE}" get pod iperf-server -o jsonpath='{.status.podIP}')
FORTIO_IP=$(kubectl -n "${NAMESPACE}" get pod fortio-server -o jsonpath='{.status.podIP}')

echo ""
echo "=== TCP Throughput (iperf3, 10s) ==="
kubectl -n "${NAMESPACE}" exec iperf-client -- iperf3 -c "${IPERF_IP}" -t 10 2>&1 | tail -3

echo ""
echo "=== HTTP Latency (fortio, 1000 RPS, 30s) ==="
kubectl -n "${NAMESPACE}" exec fortio-client -- \
    fortio load -qps 1000 -t 30s -c 50 "http://${FORTIO_IP}:8080/echo" 2>&1 | \
    grep -E "target|Sockets|All done|Ended|p50|p75|p90|p99|Code 200"

echo ""
echo "=== HTTP Max Throughput (fortio, max RPS, 10s) ==="
kubectl -n "${NAMESPACE}" exec fortio-client -- \
    fortio load -qps 0 -t 10s -c 50 "http://${FORTIO_IP}:8080/echo" 2>&1 | \
    grep -E "target|Sockets|All done|Ended|p50|p75|p90|p99|Code 200"

# Cleanup
echo ""
echo "Cleaning up..."
kubectl -n "${NAMESPACE}" delete pod iperf-server fortio-server iperf-client fortio-client --ignore-not-found

echo ""
echo "=== Performance test complete ==="
