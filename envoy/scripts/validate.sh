#!/usr/bin/env bash
set -euo pipefail

echo "=== Envoy POC Validation ==="
FAILED=0

# Check CNI
echo ""
echo "Checking CNI..."
if kubectl -n kube-system get pods -l k8s-app=cilium -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -q Running; then
    echo "[OK] Cilium is running"
elif kubectl -n calico-system get pods -l k8s-app=calico-node -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -q Running; then
    echo "[OK] Calico is running"
else
    echo "[FAIL] No CNI running"
    FAILED=1
fi

# Check SPIRE server
echo ""
echo "Checking SPIRE server..."
if kubectl -n spire-system get pods -l app.kubernetes.io/name=server -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -q Running; then
    echo "[OK] SPIRE server is running"
else
    echo "[FAIL] SPIRE server not running"
    FAILED=1
fi

# Check SPIRE agents
echo ""
echo "Checking SPIRE agents..."
AGENT_READY=$(kubectl -n spire-system get daemonset spire-agent -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
AGENT_DESIRED=$(kubectl -n spire-system get daemonset spire-agent -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
if [[ "${AGENT_READY}" -gt 0 ]] && [[ "${AGENT_READY}" == "${AGENT_DESIRED}" ]]; then
    echo "[OK] SPIRE agents ready (${AGENT_READY}/${AGENT_DESIRED})"
else
    echo "[FAIL] SPIRE agents not ready (${AGENT_READY}/${AGENT_DESIRED})"
    FAILED=1
fi

# Check Envoy proxy
echo ""
echo "Checking Envoy proxy..."
ENVOY_READY=$(kubectl -n envoy-system get daemonset envoy-proxy -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
ENVOY_DESIRED=$(kubectl -n envoy-system get daemonset envoy-proxy -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
if [[ "${ENVOY_READY}" -gt 0 ]] && [[ "${ENVOY_READY}" == "${ENVOY_DESIRED}" ]]; then
    echo "[OK] Envoy proxy ready (${ENVOY_READY}/${ENVOY_DESIRED})"
else
    echo "[FAIL] Envoy proxy not ready (${ENVOY_READY}/${ENVOY_DESIRED})"
    FAILED=1
fi

# Check ClusterSPIFFEID
echo ""
echo "Checking ClusterSPIFFEID..."
if kubectl get clusterspiffeid envoy-proxy &>/dev/null; then
    echo "[OK] ClusterSPIFFEID exists"
else
    echo "[FAIL] ClusterSPIFFEID not found"
    FAILED=1
fi

echo ""
if [[ "${FAILED}" -eq 0 ]]; then
    echo "=== All checks passed ==="
else
    echo "=== Some checks failed ==="
    exit 1
fi
