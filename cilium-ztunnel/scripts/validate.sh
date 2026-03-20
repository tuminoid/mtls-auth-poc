#!/usr/bin/env bash
set -euo pipefail

FAILED=0

echo "=== Cilium Ztunnel Validation ==="
echo ""

# Check nodes
echo "Checking nodes..."
if kubectl get nodes | grep -q "Ready"; then
    echo "[OK] Nodes are ready"
else
    echo "[FAIL] Nodes not ready"
    FAILED=1
fi
echo ""

# Check Cilium
echo "Checking Cilium pods..."
if kubectl -n kube-system get pods -l k8s-app=cilium -o jsonpath='{.items[*].status.phase}' | grep -q "Running"; then
    echo "[OK] Cilium pods running"
else
    echo "[FAIL] Cilium pods not running"
    FAILED=1
fi

# Check ztunnel config
echo "Checking ztunnel encryption config..."
if kubectl -n kube-system describe cm cilium-config 2>/dev/null | grep -q "enable-ztunnel"; then
    echo "[OK] Ztunnel encryption enabled"
    kubectl -n kube-system describe cm cilium-config | grep -E "enable-ztunnel|encrypt" | head -5
else
    echo "[FAIL] Ztunnel not enabled in config"
    FAILED=1
fi

# Check secrets
echo ""
echo "Checking ztunnel secrets..."
if kubectl -n kube-system get secret cilium-ztunnel-secrets &>/dev/null; then
    echo "[OK] cilium-ztunnel-secrets exists"
else
    echo "[FAIL] cilium-ztunnel-secrets missing"
    FAILED=1
fi

# Check enrolled namespaces
echo ""
echo "Checking namespace enrollment..."
ENROLLED=$(kubectl get namespaces -l io.cilium/mtls-enabled=true --no-headers 2>/dev/null | wc -l)
if [[ "${ENROLLED}" -ge 1 ]]; then
    echo "[OK] ${ENROLLED} namespace(s) enrolled"
    kubectl get namespaces -l io.cilium/mtls-enabled=true
else
    echo "[WARN] No namespaces enrolled yet"
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
