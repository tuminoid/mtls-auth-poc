#!/usr/bin/env bash
set -euo pipefail

echo "Creating test namespace..."
kubectl create namespace mtls-test 2>/dev/null || true

echo "Creating ClusterSPIFFEID..."
kubectl apply -f - <<EOF
apiVersion: spire.spiffe.io/v1alpha1
kind: ClusterSPIFFEID
metadata:
  name: mtls-test-workloads
spec:
  spiffeIDTemplate: "spiffe://prod.metal3.local/ns/{{ .PodMeta.Namespace }}/sa/{{ .PodSpec.ServiceAccountName }}"
  podSelector:
    matchLabels:
      spiffe.io/spiffe-id: "true"
  namespaceSelector:
    matchLabels:
      kubernetes.io/metadata.name: mtls-test
  ttl: 1h
EOF

# Wait for ClusterSPIFFEID to be processed
sleep 5

echo "Deploying server with Ghostunnel sidecar..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: server
  namespace: mtls-test
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: server
  namespace: mtls-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: server
  template:
    metadata:
      labels:
        app: server
        spiffe.io/spiffe-id: "true"
    spec:
      serviceAccountName: server
      containers:
      - name: app
        image: nginx:1.28-alpine
        ports:
        - containerPort: 80
      - name: ghostunnel
        image: ghostunnel/ghostunnel:v1.9.1
        args:
        - server
        - --listen=:8443
        - --target=localhost:80
        - --use-workload-api-addr=unix:///run/spire/agent-sockets/spire-agent.sock
        - --allow-uri-san=spiffe://prod.metal3.local/ns/mtls-test/sa/client
        ports:
        - containerPort: 8443
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
kind: Service
metadata:
  name: server
  namespace: mtls-test
spec:
  selector:
    app: server
  ports:
  - name: mtls
    port: 8443
    targetPort: 8443
  - name: http
    port: 80
    targetPort: 80
EOF

echo "Deploying client with Ghostunnel sidecar..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: client
  namespace: mtls-test
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: client
  namespace: mtls-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: client
  template:
    metadata:
      labels:
        app: client
        spiffe.io/spiffe-id: "true"
    spec:
      serviceAccountName: client
      containers:
      - name: app
        image: busybox:1.37
        command: ["sleep", "infinity"]
      - name: ghostunnel
        image: ghostunnel/ghostunnel:v1.9.1
        args:
        - client
        - --listen=localhost:9000
        - --target=server.mtls-test.svc.cluster.local:8443
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

echo "Deploying unauthorized client (no ghostunnel, different SA)..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: unauthorized
  namespace: mtls-test
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: unauthorized
  namespace: mtls-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: unauthorized
  template:
    metadata:
      labels:
        app: unauthorized
    spec:
      serviceAccountName: unauthorized
      containers:
      - name: app
        image: busybox:1.37
        command: ["sleep", "infinity"]
EOF

echo "Waiting for deployments..."
kubectl -n mtls-test rollout status deployment/server --timeout=120s
kubectl -n mtls-test rollout status deployment/client --timeout=120s
kubectl -n mtls-test rollout status deployment/unauthorized --timeout=120s

echo "Ghostunnel workloads deployed"
kubectl -n mtls-test get pods -o wide
