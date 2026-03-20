# Envoy Per-Node mTLS POC

Attempted per-node Envoy proxy with DIY iptables interception.

## Status: Incomplete (Documents Why DIY Fails)

This POC demonstrates that **node-level iptables cannot intercept pod-to-pod
traffic**. The implementation is complete but traffic bypasses Envoy.

## Key Finding

Pods have isolated network namespaces. Node-level iptables rules only see:

- Traffic from/to the host network
- Traffic from hostNetwork pods

They do NOT see traffic between regular pods because that traffic stays within
the pod network namespaces and CNI virtual interfaces.

```text
Pod A (netns A) --> veth --> CNI bridge --> veth --> Pod B (netns B)
                    ^                              ^
                    |                              |
            Node iptables NEVER sees this traffic
```

## What Works

- SPIRE server and agents deployed
- Envoy DaemonSet with SPIRE SDS integration
- Envoy configured as transparent proxy (ORIGINAL_DST clusters)
- iptables rules installed on each node

## What Doesn't Work

- Traffic interception: 0 packets redirected to Envoy
- mTLS: Not applied (traffic bypasses proxy)

## Performance (Baseline - No mTLS)

Since traffic doesn't go through Envoy, these are baseline numbers:

| Metric | Result |
| -------- | -------- |
| TCP throughput | 815 Mbps |
| HTTP p99 @ 1000 RPS | 3.9 ms |
| HTTP max QPS | 66k |

## Quick Start

```bash
make run      # Deploy and run e2e test
make perf     # Run performance test
make clean    # Delete cluster
```

## Transparent Interception Options

To make per-node proxy transparent, you need one of:

| Approach | How It Works | Complexity |
| ---------- | -------------- | ------------ |
| Per-pod init container | iptables in pod netns (istio-init) | Medium |
| CNI plugin | Inject rules when pod starts (istio-cni) | High |
| eBPF | Kernel-level interception (Cilium) | Very High |

All of these require code that runs in the pod's network namespace or at the
kernel level. Node-level iptables is insufficient.

## Lesson Learned

This POC attempted to build what Istio Ambient already provides:

| Component | This POC | Istio Ambient |
| ----------- | ---------- | --------------- |
| Identity | SPIRE | istiod |
| Per-node proxy | Envoy | ztunnel |
| Traffic interception | DIY iptables (fails) | istio-cni (works) |

The traffic interception is the hard part. It requires:

- GENEVE tunnels between pods and proxy
- iptables/eBPF rules in each pod's netns
- IP sets to track mesh membership
- Policy routing for marked packets

This is hundreds of lines of kernel networking code. Istio's `istio-cni`
implements this. Do not attempt to build it from scratch.

## Conclusion

For transparent per-node mTLS:

- Use **Istio Ambient** (production-ready)
- Use **Cilium + SPIRE** (if Cilium is your CNI)

DIY per-node proxy without CNI integration does not work.

## References

- [Istio Ambient Traffic Redirection](https://istio.io/latest/docs/ambient/architecture/traffic-redirection/)
- [Traffic Redirection with iptables and GENEVE](https://www.solo.io/blog/traffic-ambient-mesh-redirection-iptables-geneve-tunnels)
