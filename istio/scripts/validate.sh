#!/usr/bin/env bash
set -euo pipefail

echo "=== Istio Ambient POC Validation ==="
FAILED=0

# Check Cilium
echo ""
echo "Checking Cilium..."
if kubectl -n kube-system get pods -l k8s-app=cilium -o jsonpath='{.items[*].status.phase}' | grep -q Running; then
    echo "[OK] Cilium is running"
else
    echo "[FAIL] Cilium not running"
    FAILED=1
fi

# Check Cilium Istio compatibility
echo ""
echo "Checking Cilium Istio compatibility..."
if kubectl get configmaps -n kube-system cilium-config -oyaml 2>/dev/null | grep -q "cni-exclusive: \"false\""; then
    echo "[OK] Cilium CNI exclusive=false"
else
    echo "[FAIL] Cilium CNI exclusive not set to false"
    FAILED=1
fi

# Check istiod
echo ""
echo "Checking istiod..."
if kubectl -n istio-system get pods -l app=istiod -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -q Running; then
    echo "[OK] istiod is running"
else
    echo "[FAIL] istiod not running"
    FAILED=1
fi

# Check ztunnel
echo ""
echo "Checking ztunnel..."
ZTUNNEL_READY=$(kubectl -n istio-system get daemonset ztunnel -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
ZTUNNEL_DESIRED=$(kubectl -n istio-system get daemonset ztunnel -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
if [[ "${ZTUNNEL_READY}" -gt 0 ]] && [[ "${ZTUNNEL_READY}" == "${ZTUNNEL_DESIRED}" ]]; then
    echo "[OK] ztunnel DaemonSet ready (${ZTUNNEL_READY}/${ZTUNNEL_DESIRED})"
else
    echo "[FAIL] ztunnel not ready (${ZTUNNEL_READY}/${ZTUNNEL_DESIRED})"
    FAILED=1
fi

# Check istio-cni
echo ""
echo "Checking istio-cni..."
CNI_READY=$(kubectl -n istio-system get daemonset istio-cni-node -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
CNI_DESIRED=$(kubectl -n istio-system get daemonset istio-cni-node -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
if [[ "${CNI_READY}" -gt 0 ]] && [[ "${CNI_READY}" == "${CNI_DESIRED}" ]]; then
    echo "[OK] istio-cni DaemonSet ready (${CNI_READY}/${CNI_DESIRED})"
else
    echo "[FAIL] istio-cni not ready (${CNI_READY}/${CNI_DESIRED})"
    FAILED=1
fi

# Check WireGuard
echo ""
echo "Checking WireGuard encryption..."
if kubectl -n kube-system exec ds/cilium -- cilium status 2>/dev/null | grep -q "Encryption.*Wireguard"; then
    echo "[OK] WireGuard encryption enabled"
else
    echo "[WARN] WireGuard status unclear"
fi

echo ""
if [[ "${FAILED}" -eq 0 ]]; then
    echo "=== All checks passed ==="
else
    echo "=== Some checks failed ==="
    exit 1
fi
