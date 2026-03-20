#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="mtls-test"

echo "Creating test namespace: ${NAMESPACE}"
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "Applying CiliumNetworkPolicy requiring authentication..."
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
        - {}
      authentication:
        mode: required
EOF

echo "Deploying server pod..."
kubectl -n "${NAMESPACE}" run server --image=nginx:1.28-alpine --port=80 --restart=Never --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "${NAMESPACE}" expose pod server --port=80 --dry-run=client -o yaml | kubectl apply -f -

echo "Deploying client pod..."
kubectl -n "${NAMESPACE}" run client --image=curlimages/curl:8.18.0 --restart=Never --command --dry-run=client -o yaml -- sleep 3600 | kubectl apply -f -

echo "Waiting for pods to be ready..."
kubectl -n "${NAMESPACE}" wait --for=condition=ready pod/server --timeout=120s
kubectl -n "${NAMESPACE}" wait --for=condition=ready pod/client --timeout=120s

echo "Waiting for SPIFFE identities (10s)..."
sleep 10

echo "Testing connectivity..."
if kubectl -n "${NAMESPACE}" exec client -- curl -s --max-time 5 http://server >/dev/null; then
    echo "[OK] Client can reach server with mTLS"
else
    echo "[FAIL] Client cannot reach server"
    exit 1
fi

echo "Checking Cilium auth table..."
kubectl -n kube-system exec ds/cilium -- cilium bpf auth list 2>/dev/null || echo "(auth table check skipped)"

echo ""
echo "Demo complete. Cleanup with: kubectl delete namespace ${NAMESPACE}"
