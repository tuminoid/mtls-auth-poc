#!/usr/bin/env bash
set -euo pipefail

# Ghostunnel TRANSPARENT perf test: init container injects iptables rules
# Apps connect normally, traffic is intercepted and routed through ghostunnel

NAMESPACE="mtls-test"
SERVER_NODE="mtls-poc-worker"
CLIENT_NODE="mtls-poc-worker2"

echo "=== Ghostunnel TRANSPARENT mTLS Performance Test ==="
echo "Init containers inject iptables rules - apps connect normally"
echo ""

# Clean up any existing pods
kubectl -n "${NAMESPACE}" delete pod iperf-server fortio-server iperf-client fortio-client --ignore-not-found --wait 2>/dev/null || true

echo "Deploying server pods with ghostunnel + init container..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: iperf-server
  namespace: ${NAMESPACE}
  labels:
    spiffe.io/spiffe-id: "true"
spec:
  serviceAccountName: server
  nodeName: ${SERVER_NODE}
  initContainers:
  - name: ghostunnel-init
    image: alpine:3.23
    command: ["true"]  # No iptables needed on server - ghostunnel listens directly
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
    spiffe.io/spiffe-id: "true"
spec:
  serviceAccountName: server
  nodeName: ${SERVER_NODE}
  initContainers:
  - name: ghostunnel-init
    image: alpine:3.23
    command: ["true"]  # No iptables needed on server
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
echo "iperf server: ${IPERF_IP}:5201 (intercepted -> ghostunnel -> iperf)"
echo "fortio server: ${FORTIO_IP}:8080 (intercepted -> ghostunnel -> fortio)"

echo ""
echo "Deploying client pods with ghostunnel + init container..."
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
  initContainers:
  - name: ghostunnel-init
    image: alpine:3.23
    securityContext:
      capabilities:
        add: [NET_ADMIN]
    command: [sh, -c]
    args:
    - |
      apk add --no-cache iptables
      # Redirect outbound traffic to server:5201 through ghostunnel
      # Skip traffic from root (UID 0) - ghostunnel runs as root
      iptables -t nat -A OUTPUT -p tcp -d ${IPERF_IP} --dport 5201 -m owner ! --uid-owner 0 -j REDIRECT --to-port 15201
      iptables -t nat -L -n -v
  containers:
  - name: iperf
    image: networkstatic/iperf3:latest
    command: ["sleep", "infinity"]
  - name: ghostunnel
    image: ghostunnel/ghostunnel:v1.9.1
    args:
    - client
    - --listen=127.0.0.1:15201
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
  initContainers:
  - name: ghostunnel-init
    image: alpine:3.23
    securityContext:
      capabilities:
        add: [NET_ADMIN]
    command: [sh, -c]
    args:
    - |
      apk add --no-cache iptables
      iptables -t nat -A OUTPUT -p tcp -d ${FORTIO_IP} --dport 8080 -m owner ! --uid-owner 0 -j REDIRECT --to-port 19000
  containers:
  - name: fortio
    image: fortio/fortio:1.73.2
    args: ["server", "-http-port", "0", "-grpc-port", "0"]
  - name: ghostunnel
    image: ghostunnel/ghostunnel:v1.9.1
    args:
    - client
    - --listen=127.0.0.1:19000
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

sleep 5

echo ""
echo "=== TCP Throughput - TRANSPARENT (iperf3, 10s) ==="
echo "Client connects to ${IPERF_IP}:5201 (iptables intercepts -> ghostunnel -> mTLS)"
kubectl -n "${NAMESPACE}" exec iperf-client -c iperf -- \
    iperf3 -c "${IPERF_IP}" -p 5201 -t 10 2>&1 | tail -3

echo ""
echo "=== HTTP Latency - TRANSPARENT (fortio, 1000 RPS, 30s) ==="
echo "Client connects to ${FORTIO_IP}:8080 (iptables intercepts -> ghostunnel -> mTLS)"
kubectl -n "${NAMESPACE}" exec fortio-client -c fortio -- \
    fortio load -qps 1000 -t 30s -c 50 "http://${FORTIO_IP}:8080/echo" 2>&1 | \
    grep -E "target|Sockets|All done|Ended|p50|p75|p90|p99|Code 200"

echo ""
echo "=== HTTP Max Throughput - TRANSPARENT (fortio, max RPS, 10s) ==="
kubectl -n "${NAMESPACE}" exec fortio-client -c fortio -- \
    fortio load -qps 0 -t 10s -c 50 "http://${FORTIO_IP}:8080/echo" 2>&1 | \
    grep -E "target|Sockets|All done|Ended|p50|p75|p90|p99|Code 200"

echo ""
echo "Cleaning up..."
kubectl -n "${NAMESPACE}" delete pod iperf-server fortio-server iperf-client fortio-client --ignore-not-found

echo ""
echo "=== TRANSPARENT Ghostunnel performance test complete ==="
