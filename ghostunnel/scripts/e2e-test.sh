#!/usr/bin/env bash
set -euo pipefail

echo "=== Ghostunnel mTLS E2E Test ==="

# Wait for pods to be fully ready
sleep 5

echo ""
echo "=== Test 1: Positive - Client via Ghostunnel tunnel ==="
echo "Client connects through its ghostunnel sidecar (localhost:9000) to server's ghostunnel (8443)"

if kubectl -n mtls-test exec deploy/client -c app -- wget -q -O - --timeout=10 http://localhost:9000 | grep -q "nginx"; then
    echo "PASS: Client successfully connected via mTLS tunnel"
else
    echo "FAIL: Client could not connect via mTLS tunnel"
    echo "Checking ghostunnel logs..."
    kubectl -n mtls-test logs deploy/client -c ghostunnel --tail=10 || true
    kubectl -n mtls-test logs deploy/server -c ghostunnel --tail=10 || true
    exit 1
fi

echo ""
echo "=== Test 2: Negative - Unauthorized client direct to mTLS port ==="
echo "Unauthorized pod tries to connect directly to server:8443 (should fail - no valid cert)"

if kubectl -n mtls-test exec deploy/unauthorized -c app -- wget -q -O - --timeout=5 http://server.mtls-test.svc.cluster.local:8443 2>/dev/null; then
    echo "FAIL: Unauthorized client connected to mTLS port (should have been rejected)"
    exit 1
else
    echo "PASS: Unauthorized client correctly rejected by mTLS"
fi

echo ""
echo "=== Test 3: Negative - Unauthorized client to plaintext port ==="
echo "Unauthorized pod tries to connect to server:80 (plaintext, should work - no mTLS enforcement)"
echo "This demonstrates that mTLS is only enforced on port 8443"

if kubectl -n mtls-test exec deploy/unauthorized -c app -- wget -q -O - --timeout=5 http://server.mtls-test.svc.cluster.local:80 | grep -q "nginx"; then
    echo "INFO: Plaintext port accessible (expected - mTLS only on 8443)"
else
    echo "INFO: Plaintext port not accessible (network policy may be blocking)"
fi

echo ""
echo "=== All mTLS tests passed ==="
