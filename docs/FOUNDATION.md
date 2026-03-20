# Foundation: SPIRE and CNI Setup

Deploy core identity and encryption infrastructure for mTLS.

## Prerequisites

- Kubernetes cluster with Helm 3.x
- kubectl access to cluster
- Note current CNI installation method for rollback

## System Exclusions

### The Problem

Kubernetes control plane components and critical system workloads must operate
independently of SPIRE/Cilium mTLS. Enforcing mTLS on these creates circular
dependencies.

### Bootstrap Order

```text
1. Control Plane (static pods/systemd) - No CNI dependency
2. CNI (Cilium/Calico)                 - Pod networking available
3. SPIRE Server                        - Identity infrastructure
4. SPIRE Agents (DaemonSet)            - Node-level identity
5. SPIRE Controller Manager            - Kubernetes integration
6. Cilium Mutual Auth                  - mTLS enforcement
7. Application Workloads               - mTLS protected
```

### Why Control Plane Is Safe

Static pods (typical for kubeadm clusters):

- kube-apiserver, etcd, controller-manager, scheduler run as static pods
- Managed directly by kubelet, not through API server
- Use host networking (`hostNetwork: true`), bypassing CNI entirely
- Cilium network policies don't apply to host-networked pods

### Namespaces to Exclude

| Namespace | Reason |
| --------- | ------ |
| `kube-system` | Core cluster components, CNI, DNS |
| `kube-node-lease` | Node heartbeats |
| `kube-public` | Cluster info |
| `spire-system` | SPIRE itself (chicken-egg) |
| `cert-manager` | Certificate infrastructure |
| `cilium-*` | Cilium operator namespace if separate |

### Failure Modes

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| DNS resolution fails | CoreDNS blocked by mTLS | Exclude kube-system |
| API server unreachable | Unlikely (host network) | Check custom API setup |
| SPIRE agents can't start | Circular dependency | Exclude spire-system |
| Cilium pods crash-loop | Missing identity | Exclude kube-system |

## Step 1: Deploy PostgreSQL for SPIRE Backend

Skip if using existing PostgreSQL.

```bash
# Create namespace
kubectl create namespace spire-system

# Generate password and store in secret
kubectl -n spire-system create secret generic spire-db-credentials \
  --from-literal=password=$(openssl rand -base64 24)

# Deploy PostgreSQL
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install spire-db bitnami/postgresql \
  --namespace spire-system \
  --set auth.database=spire \
  --set auth.username=spire \
  --set auth.existingSecret=spire-db-credentials \
  --set auth.secretKeys.userPasswordKey=password

# Wait for PostgreSQL to be ready
kubectl -n spire-system wait --for=condition=ready pod \
  -l app.kubernetes.io/name=postgresql --timeout=120s
```

## Step 2: Deploy SPIRE Server

```bash
# Get password from secret for connection string
DB_PASS=$(kubectl -n spire-system get secret spire-db-credentials \
  -o jsonpath='{.data.password}' | base64 -d)

helm repo add spiffe https://spiffe.github.io/helm-charts-hardened
helm install spire spiffe/spire \
  --namespace spire-system \
  --set global.spire.trustDomain=prod.metal3.local \
  --set spire-server.replicaCount=3 \
  --set spire-server.dataStore.sql.databaseType=postgres \
  --set spire-server.dataStore.sql.connectionString="\
dbname=spire user=spire password=${DB_PASS} host=spire-db-postgresql"

unset DB_PASS
```

## Step 3: Verify SPIRE Server

```bash
kubectl -n spire-system wait --for=condition=ready pod \
  -l app.kubernetes.io/name=spire-server --timeout=180s
kubectl -n spire-system logs -l app.kubernetes.io/name=spire-server \
  --tail=50 | grep -i "started"
```

## Step 4: Deploy SPIRE Controller Manager

```bash
kubectl apply -f https://github.com/spiffe/spire-controller-manager/releases/latest/download/spire-controller-manager.yaml
```

Verify:

```bash
kubectl -n spire-system wait --for=condition=ready pod \
  -l app=spire-controller-manager --timeout=60s
```

## Step 5: Verify SPIRE Agents

Agents are deployed as DaemonSet by the Helm chart.

```bash
kubectl -n spire-system get pods -l app.kubernetes.io/name=spire-agent
kubectl -n spire-system exec -it \
  $(kubectl -n spire-system get pod -l app.kubernetes.io/name=spire-agent \
    -o jsonpath='{.items[0].metadata.name}') \
  -- /opt/spire/bin/spire-agent healthcheck
```

## Step 6: Backup Current CNI Configuration

Before migration, save current config for rollback:

```bash
# For operator-based Calico
kubectl get installation default -o yaml > calico-installation-backup.yaml
kubectl get tigerastatuses -o yaml > calico-status-backup.yaml

# For manifest-based Calico
kubectl get daemonset -n kube-system calico-node -o yaml > calico-backup.yaml
```

## Step 7: Migrate to Cilium (if needed)

This is a disruptive operation. Plan maintenance window.

```bash
# Remove Calico (choose based on your installation)
# If operator-based:
kubectl delete tigerastatuses --all
kubectl delete installation default
kubectl delete -f https://docs.tigera.io/calico/latest/manifests/tigera-operator.yaml

# If manifest-based:
kubectl delete -f https://docs.projectcalico.org/manifests/calico.yaml

# Wait for Calico pods to terminate
kubectl -n kube-system wait --for=delete pod -l k8s-app=calico-node \
  --timeout=120s

# Install Cilium with WireGuard
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium \
  --namespace kube-system \
  --set encryption.enabled=true \
  --set encryption.type=wireguard \
  --set encryption.wireguard.userspaceFallback=false \
  --set kubeProxyReplacement=true
```

## Step 8: Verify Cilium and WireGuard

```bash
kubectl -n kube-system wait --for=condition=ready pod \
  -l k8s-app=cilium --timeout=180s
cilium status
cilium encryption status
```

## ClusterSPIFFEID Configuration

When creating ClusterSPIFFEID resources, always exclude system namespaces:

```yaml
apiVersion: spire.spiffe.io/v1alpha1
kind: ClusterSPIFFEID
metadata:
  name: default-workload-identity
spec:
  spiffeIDTemplate: >-
    spiffe://prod.metal3.local/ns/{{ .PodMeta.Namespace }}/sa/{{
    .PodSpec.ServiceAccountName }}
  podSelector: {}
  namespaceSelector:
    matchExpressions:
    - key: kubernetes.io/metadata.name
      operator: NotIn
      values:
      - kube-system
      - kube-node-lease
      - kube-public
      - spire-system
      - cert-manager
  ttl: 1h
```

## CiliumNetworkPolicy Configuration

Never apply `authentication.mode: required` cluster-wide. Target specific
namespaces:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: require-auth
  namespace: my-app  # Always namespace-scoped
spec:
  endpointSelector: {}
  ingress:
  - fromEndpoints:
    - {}
    authentication:
      mode: required
```

### Alternative: CiliumClusterwideNetworkPolicy with Exclusions

If cluster-wide policy is needed, exclude system namespaces:

```yaml
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: require-auth-apps
spec:
  endpointSelector:
    matchExpressions:
    - key: io.kubernetes.pod.namespace
      operator: NotIn
      values:
      - kube-system
      - kube-node-lease
      - kube-public
      - spire-system
      - cert-manager
  ingress:
  - fromEndpoints:
    - {}
    authentication:
      mode: required
```

## Cilium Agent Identity for Delegated API

Cilium agents need a SPIFFE identity with admin privileges to use SPIRE's
Delegated Identity API. This allows Cilium to request identities ON BEHALF
of workload pods.

### Why ClusterStaticEntry (not ClusterSPIFFEID)

- ClusterStaticEntry supports `admin: true` for Delegated Identity API access
- Static entries are appropriate for infrastructure components
- ClusterSPIFFEID lacks the admin flag required for delegated operations

### ClusterStaticEntry for Cilium

Create before enabling Cilium mutual authentication:

```yaml
apiVersion: spire.spiffe.io/v1alpha1
kind: ClusterStaticEntry
metadata:
  name: cilium-agent
spec:
  spiffeID: "spiffe://prod.metal3.local/cilium-agent"
  parentID: "spiffe://prod.metal3.local/spire/agent/k8s_psat/kind-mtls"
  selectors:
  - "k8s:ns:kube-system"
  - "k8s:sa:cilium"
  admin: true
```

Note: Adjust `parentID` to match your cluster name in the SPIRE agent ID.

### Verifying Cilium Entry

```bash
# Check entry was created
kubectl -n spire-system exec -it \
  $(kubectl -n spire-system get pod \
    -l app.kubernetes.io/name=spire-server \
    -o jsonpath='{.items[0].metadata.name}') \
  -- /opt/spire/bin/spire-server entry show | grep cilium-agent

# Verify Cilium can connect to SPIRE (after enabling mutual auth)
kubectl -n kube-system logs -l k8s-app=cilium | grep -i spire
```

## Verifying System Pods Excluded

Check that system pods don't have SPIRE entries:

```bash
# Should return no entries for kube-system
kubectl -n spire-system exec -it \
  $(kubectl -n spire-system get pod \
    -l app.kubernetes.io/name=spire-server \
    -o jsonpath='{.items[0].metadata.name}') \
  -- /opt/spire/bin/spire-server entry show | grep kube-system

# Verify kube-system pods still communicate
kubectl -n kube-system exec -it \
  $(kubectl -n kube-system get pod -l k8s-app=coredns \
    -o jsonpath='{.items[0].metadata.name}') \
  -c coredns -- nslookup kubernetes.default
```

## Validation Checklist

- [ ] SPIRE server pods running (3 replicas)
- [ ] SPIRE agents running on all nodes
- [ ] SPIRE controller manager running
- [ ] Cilium pods running on all nodes
- [ ] WireGuard encryption active between nodes
- [ ] No network connectivity issues for existing workloads
- [ ] System namespaces excluded from ClusterSPIFFEID

## Rollback

SPIRE:

```bash
helm uninstall spire -n spire-system
helm uninstall spire-db -n spire-system
```

Cilium (restore Calico from backup):

```bash
helm uninstall cilium -n kube-system
# Restore using your saved backup files
kubectl apply -f calico-backup.yaml  # or calico-installation-backup.yaml
```
