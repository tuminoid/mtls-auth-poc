# Agent Instructions: Envoy Per-Node POC

## Goal

Implement CNI-agnostic mTLS using standalone SPIRE + per-node Envoy proxy.

## Key Files

- `manifests/spire-values.yaml` - Standalone SPIRE config
- `manifests/cilium-values.yaml` - Cilium CNI config
- `manifests/envoy-config.yaml` - Envoy with SPIRE SDS
- `manifests/envoy-daemonset.yaml` - Per-node Envoy deployment
- `scripts/deploy-cni.sh` - CNI=cilium|calico

## Commands

Always use Makefile targets:

```bash
make run              # Full e2e with Cilium
make run CNI=calico   # Full e2e with Calico
make clean            # Cleanup
make validate         # Check deployment
```

## CNI Selection

Set `CNI` environment variable:

- `CNI=cilium` (default) - Cilium with WireGuard
- `CNI=calico` - Calico with WireGuard

## Trust Domain

`prod.metal3.local`

## Debugging

```bash
# Check SPIRE
kubectl -n spire-system get pods
kubectl -n spire-system exec spire-server-0 -c spire-server -- \
    /opt/spire/bin/spire-server entry show

# Check Envoy
kubectl -n envoy-system get pods
kubectl -n envoy-system logs ds/envoy-proxy
kubectl -n envoy-system exec ds/envoy-proxy -- curl localhost:9901/stats
```
