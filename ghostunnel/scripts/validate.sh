#!/usr/bin/env bash
set -euo pipefail

echo "=== Ghostunnel POC Validation ==="

ERRORS=0

echo "Checking SPIRE server..."
if kubectl -n spire-system get pod -l app.kubernetes.io/name=server -o jsonpath='{.items[0].status.phase}' | grep -q Running; then
    echo "  SPIRE server: Running"
else
    echo "  SPIRE server: NOT RUNNING"
    ERRORS=$((ERRORS + 1))
fi

echo "Checking SPIRE agents..."
AGENT_READY=$(kubectl -n spire-system get ds spire-agent -o jsonpath='{.status.numberReady}')
AGENT_DESIRED=$(kubectl -n spire-system get ds spire-agent -o jsonpath='{.status.desiredNumberScheduled}')
if [[ "${AGENT_READY}" = "${AGENT_DESIRED}" ]]; then
    echo "  SPIRE agents: ${AGENT_READY}/${AGENT_DESIRED} ready"
else
    echo "  SPIRE agents: ${AGENT_READY}/${AGENT_DESIRED} ready (INCOMPLETE)"
    ERRORS=$((ERRORS + 1))
fi

echo "Checking SPIFFE entries..."
ENTRIES=$(kubectl -n spire-system exec spire-server-0 -c spire-server -- /opt/spire/bin/spire-server entry show 2>/dev/null | grep -c "Entry ID" || echo "0")
echo "  SPIFFE entries: ${ENTRIES}"

echo "Checking Ghostunnel pods..."
for POD in server client; do
    if kubectl -n mtls-test get pod -l "app=${POD}" -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running; then
        echo "  ${POD}: Running"
        # Check ghostunnel container
        if kubectl -n mtls-test logs "deploy/${POD}" -c ghostunnel 2>&1 | grep -q "listening"; then
            echo "    ghostunnel sidecar: listening"
        else
            echo "    ghostunnel sidecar: starting..."
        fi
    else
        echo "  ${POD}: NOT RUNNING"
        ERRORS=$((ERRORS + 1))
    fi
done

echo ""
if [[ "${ERRORS}" -eq 0 ]]; then
    echo "Validation PASSED"
else
    echo "Validation FAILED with ${ERRORS} error(s)"
    exit 1
fi
