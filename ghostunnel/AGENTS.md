# Agent Instructions: Ghostunnel Sidecar POC

## Goal

Implement mTLS using standalone SPIRE + Ghostunnel sidecars (explicit proxy).

## Key Files

- `manifests/spire-values.yaml` - Standalone SPIRE config
- `manifests/cilium-values.yaml` - Cilium CNI config
- `scripts/deploy-ghostunnel.sh` - Deploys server, client, unauthorized pods

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

# Check Ghostunnel
kubectl -n mtls-test get pods
kubectl -n mtls-test logs deploy/server -c ghostunnel
kubectl -n mtls-test logs deploy/client -c ghostunnel
```
