# Agent Instructions: Istio Ambient POC

## Goal

Implement and test mTLS authentication using Istio Ambient mode.

## Key Files

- `manifests/cilium-values.yaml` - Cilium with Istio compatibility
- `manifests/kind-config.yaml` - Kind cluster config
- `scripts/deploy-cilium.sh` - Cilium with dynamic API server detection
- `scripts/deploy-istio.sh` - Istio Ambient 1.27.0
- `scripts/e2e-test.sh` - Tests with PeerAuthentication STRICT

## Commands

Always use Makefile targets:

```bash
make run       # Full e2e
make clean     # Cleanup
make validate  # Check deployment
```

## Istio Version

1.27.0 (configurable via `ISTIO_VERSION` env var)

## Testing

E2E test verifies:

1. Cross-node traffic via ztunnel works
1. Plaintext traffic from non-ambient namespace is blocked (STRICT mTLS)

## Cilium Compatibility

Required settings for Istio:

- `cni.exclusive: false` - Allow CNI chaining
- `socketLB.hostNamespaceOnly: true` - Don't interfere with ztunnel

## Debugging

```bash
# Check Istio components
kubectl -n istio-system get pods

# Check ztunnel logs
kubectl logs -n istio-system daemonset/ztunnel

# Check ambient enrollment
kubectl get namespace mtls-test -o jsonpath='{.metadata.labels}'

# Check PeerAuthentication
kubectl -n mtls-test get peerauthentication
```

## Ambient Mode Labels

Enable ambient for namespace:

```bash
kubectl label namespace <ns> istio.io/dataplane-mode=ambient
```
