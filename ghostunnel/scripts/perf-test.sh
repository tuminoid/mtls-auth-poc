#!/usr/bin/env bash
set -euo pipefail

# Ghostunnel-specific perf test: routes traffic through ghostunnel sidecars

NAMESPACE="mtls-test"
SERVER_NODE="mtls-poc-worker"
CLIENT_NODE="mtls-poc-worker2"

echo "=== Ghostunnel mTLS Performance Test ==="
echo "Traffic routes through ghostunnel sidecars (client -> mTLS -> server)"
echo ""

echo "Deploying perf pods with ghostunnel sidecars..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: iperf-server
  namespace: ${NAMESPACE}
  labels:
    app: iperf-server
    spiffe.io/spiffe-id: "true"
spec:
  serviceAccountName: server
  nodeName: ${SERVER_NODE}
  containers:
  - name: iperf
    image: networkstatic/iperf3:latest
    args: ["-s"]
  - name: ghostunnel
    image: ghostunnel/ghostunnel:v1.9.1
    args:
    - server
    - --listen=:15201
    - --target=localhost:5201
    - --use-workload-api-addr=unix:///run/spire/agent-sockets/spire-agent.sock
    - --allow-uri-san=spiffe://prod.metal3.local/ns/mtls-test/sa/client
    volumeMounts:
    - name: spire-socket
      mountPath: /run/spire/agent-sockets
      readOnly: true
  volumes:
  - name: spire-socket
    hostPath:
      path: /run/spire/agent-sockets
      type: Directory
---
apiVersion: v1
kind: Pod
metadata:
  name: fortio-server
  namespace: ${NAMESPACE}
  labels:
    app: fortio-server
    spiffe.io/spiffe-id: "true"
spec:
  serviceAccountName: server
  nodeName: ${SERVER_NODE}
  containers:
  - name: fortio
    image: fortio/fortio:1.73.2
    args: ["server"]
  - name: ghostunnel
    image: ghostunnel/ghostunnel:v1.9.1
    args:
    - server
    - --listen=:18443
    - --target=localhost:8080
    - --use-workload-api-addr=unix:///run/spire/agent-sockets/spire-agent.sock
    - --allow-uri-san=spiffe://prod.metal3.local/ns/mtls-test/sa/client
    volumeMounts:
    - name: spire-socket
      mountPath: /run/spire/agent-sockets
      readOnly: true
  volumes:
  - name: spire-socket
    hostPath:
      path: /run/spire/agent-sockets
      type: Directory
EOF

echo "Waiting for server pods..."
kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod/iperf-server pod/fortio-server --timeout=120s

IPERF_IP=$(kubectl -n "${NAMESPACE}" get pod iperf-server -o jsonpath='{.status.podIP}')
FORTIO_IP=$(kubectl -n "${NAMESPACE}" get pod fortio-server -o jsonpath='{.status.podIP}')

echo "Deploying client pods with ghostunnel sidecars..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: iperf-client
  namespace: ${NAMESPACE}
  labels:
    spiffe.io/spiffe-id: "true"
spec:
  serviceAccountName: client
  nodeName: ${CLIENT_NODE}
  containers:
  - name: iperf
    image: networkstatic/iperf3:latest
    command: ["sleep", "infinity"]
  - name: ghostunnel
    image: ghostunnel/ghostunnel:v1.9.1
    args:
    - client
    - --listen=localhost:15201
    - --target=${IPERF_IP}:15201
    - --use-workload-api-addr=unix:///run/spire/agent-sockets/spire-agent.sock
    - --verify-uri-san=spiffe://prod.metal3.local/ns/mtls-test/sa/server
    volumeMounts:
    - name: spire-socket
      mountPath: /run/spire/agent-sockets
      readOnly: true
  volumes:
  - name: spire-socket
    hostPath:
      path: /run/spire/agent-sockets
      type: Directory
---
apiVersion: v1
kind: Pod
metadata:
  name: fortio-client
  namespace: ${NAMESPACE}
  labels:
    spiffe.io/spiffe-id: "true"
spec:
  serviceAccountName: client
  nodeName: ${CLIENT_NODE}
  containers:
  - name: fortio
    image: fortio/fortio:1.73.2
    args: ["server", "-http-port", "0", "-grpc-port", "0"]
  - name: ghostunnel
    image: ghostunnel/ghostunnel:v1.9.1
    args:
    - client
    - --listen=localhost:19000
    - --target=${FORTIO_IP}:18443
    - --use-workload-api-addr=unix:///run/spire/agent-sockets/spire-agent.sock
    - --verify-uri-san=spiffe://prod.metal3.local/ns/mtls-test/sa/server
    volumeMounts:
    - name: spire-socket
      mountPath: /run/spire/agent-sockets
      readOnly: true
  volumes:
  - name: spire-socket
    hostPath:
      path: /run/spire/agent-sockets
      type: Directory
EOF

echo "Waiting for client pods..."
kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod/iperf-client pod/fortio-client --timeout=120s

echo ""
echo "Server node: ${SERVER_NODE}"
echo "Client node: ${CLIENT_NODE}"

# Wait for ghostunnel to establish connections
sleep 5

echo ""
echo "=== TCP Throughput via Ghostunnel (iperf3, 10s) ==="
echo "Path: iperf -> ghostunnel-client -> mTLS -> ghostunnel-server -> iperf"
kubectl -n "${NAMESPACE}" exec iperf-client -c iperf -- \
    iperf3 -c 127.0.0.1 -p 15201 -t 10 2>&1 | tail -3

echo ""
echo "=== HTTP Latency via Ghostunnel (fortio, 1000 RPS, 30s) ==="
echo "Path: fortio -> ghostunnel-client -> mTLS -> ghostunnel-server -> fortio"
kubectl -n "${NAMESPACE}" exec fortio-client -c fortio -- \
    fortio load -qps 1000 -t 30s -c 50 "http://localhost:19000/echo" 2>&1 | \
    grep -E "target|Sockets|All done|Ended|p50|p75|p90|p99|Code 200"

echo ""
echo "=== HTTP Max Throughput via Ghostunnel (fortio, max RPS, 10s) ==="
kubectl -n "${NAMESPACE}" exec fortio-client -c fortio -- \
    fortio load -qps 0 -t 10s -c 50 "http://localhost:19000/echo" 2>&1 | \
    grep -E "target|Sockets|All done|Ended|p50|p75|p90|p99|Code 200"

# Cleanup
echo ""
echo "Cleaning up perf pods..."
kubectl -n "${NAMESPACE}" delete pod iperf-server fortio-server iperf-client fortio-client --ignore-not-found

echo ""
echo "=== Performance test complete ==="
