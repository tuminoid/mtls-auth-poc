# Agent Instructions: Cilium + SPIRE POC

## Goal

Implement and test mTLS authentication using Cilium's built-in SPIRE.

## Key Files

- `manifests/cilium-values.yaml` - Base Cilium config (WireGuard only)
- `manifests/cilium-mtls-values.yaml` - Cilium with SPIRE and mutual auth
- `manifests/kind-config.yaml` - Kind cluster config
- `scripts/enable-mtls.sh` - Upgrades Cilium with SPIRE
- `scripts/e2e-test.sh` - Runs positive and negative tests

## Commands

Always use Makefile targets:

```bash
make run       # Full e2e
make clean     # Cleanup
make validate  # Check deployment
```

## Trust Domain

`prod.metal3.local`

## Testing

E2E test verifies:

1. Cross-node authenticated traffic works
1. Cross-namespace traffic from same node is blocked (identity policy)

## Debugging

```bash
# Check SPIRE
kubectl -n cilium-spire get pods
kubectl -n cilium-spire exec spire-server-0 -c spire-server -- \
  /opt/spire/bin/spire-server entry show

# Check Cilium auth
kubectl -n kube-system logs ds/cilium | grep -i spire
kubectl -n kube-system exec ds/cilium -- cilium status | grep -i auth
```
