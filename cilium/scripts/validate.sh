#!/usr/bin/env bash
set -euo pipefail

FAILED=0

# Detect SPIRE namespace (cilium-spire for built-in, spire-system for external)
if kubectl get namespace cilium-spire &>/dev/null; then
    SPIRE_NS="cilium-spire"
    SPIRE_SERVER_LABEL="app=spire-server"
    SPIRE_AGENT_LABEL="app=spire-agent"
else
    SPIRE_NS="spire-system"
    SPIRE_SERVER_LABEL="app.kubernetes.io/name=server"
    SPIRE_AGENT_LABEL="app.kubernetes.io/name=agent"
fi

echo "=== Phase 1 Validation ==="
echo ""

# Check nodes
echo "Checking nodes..."
if kubectl get nodes | grep -q "Ready"; then
    echo "[OK] Nodes are ready"
    kubectl get nodes
else
    echo "[FAIL] Nodes not ready"
    FAILED=1
fi
echo ""

# Check Cilium
echo "Checking Cilium..."
if kubectl -n kube-system get pods -l k8s-app=cilium -o jsonpath='{.items[*].status.phase}' | grep -q "Running"; then
    echo "[OK] Cilium pods running"
else
    echo "[FAIL] Cilium pods not running"
    FAILED=1
fi

# Check WireGuard encryption
echo "Checking WireGuard encryption..."
CILIUM_POD=$(kubectl -n kube-system get pod -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}')
if kubectl -n kube-system exec "${CILIUM_POD}" -- cilium encrypt status 2>/dev/null | grep -q "Encryption"; then
    echo "[OK] WireGuard encryption enabled"
    kubectl -n kube-system exec "${CILIUM_POD}" -- cilium encrypt status
else
    echo "[WARN] Could not verify WireGuard status"
fi
echo ""

# Check SPIRE server
echo "Checking SPIRE server (namespace: ${SPIRE_NS})..."
if kubectl -n "${SPIRE_NS}" get pods -l "${SPIRE_SERVER_LABEL}" -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -q "Running"; then
    echo "[OK] SPIRE server running"
else
    echo "[FAIL] SPIRE server not running"
    FAILED=1
fi

# Check SPIRE agents
echo "Checking SPIRE agents..."
AGENT_COUNT=$(kubectl -n "${SPIRE_NS}" get pods -l "${SPIRE_AGENT_LABEL}" --no-headers 2>/dev/null | grep -c "Running" || echo 0)
if [[ "${AGENT_COUNT}" -ge 1 ]]; then
    echo "[OK] SPIRE agents running (${AGENT_COUNT} agents)"
else
    echo "[FAIL] SPIRE agents not running"
    FAILED=1
fi
echo ""

# Phase 2 checks (check for Cilium mutual auth)
echo "=== Phase 2 Validation ==="
echo ""

# Check Cilium mutual auth
echo "Checking Cilium mutual authentication..."
if kubectl -n kube-system logs ds/cilium 2>/dev/null | grep -q "Spire Delegate API Client is running"; then
    echo "[OK] Cilium SPIRE integration active"
elif kubectl -n kube-system logs ds/cilium 2>/dev/null | grep -q "mesh-auth-mutual-enabled='true'"; then
    echo "[OK] Cilium mutual auth enabled"
else
    echo "[WARN] Cilium SPIRE integration status unclear"
fi

# Summary
echo ""
echo "=== Validation Summary ==="
if [[ "${FAILED}" -eq 0 ]]; then
    echo "Validation PASSED"
    exit 0
else
    echo "Validation FAILED"
    exit 1
fi
