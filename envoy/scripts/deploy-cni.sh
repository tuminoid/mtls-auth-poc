#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# CNI selection: cilium (default) or calico
CNI="${CNI:-cilium}"

echo "Installing CNI: ${CNI}"

case "${CNI}" in
    cilium)
        helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
        helm repo update cilium

        # Get API server endpoint for Kind
        API_SERVER_IP=$(kubectl get endpoints kubernetes -o jsonpath='{.subsets[0].addresses[0].ip}')
        API_SERVER_PORT=$(kubectl get endpoints kubernetes -o jsonpath='{.subsets[0].ports[0].port}')

        helm install cilium cilium/cilium \
            --version 1.19.0 \
            --namespace kube-system \
            --values "${REPO_ROOT}/manifests/cilium-values.yaml" \
            --set k8sServiceHost="${API_SERVER_IP}" \
            --set k8sServicePort="${API_SERVER_PORT}" \
            --wait

        kubectl -n kube-system rollout status daemonset/cilium --timeout=300s
        echo "Cilium installed with WireGuard"
        ;;

    calico)
        # Install Calico operator
        kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/tigera-operator.yaml 2>/dev/null || true

        # Install Calico with WireGuard
        kubectl apply -f - <<EOF
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    bgp: Disabled
    ipPools:
    - cidr: 10.244.0.0/16
      encapsulation: WireguardCrossSubnet
EOF

        echo "Waiting for Calico..."
        sleep 30
        kubectl wait --for=condition=Available tigerastatus/calico --timeout=300s || true
        kubectl -n calico-system rollout status daemonset/calico-node --timeout=300s
        echo "Calico installed with WireGuard"
        ;;

    *)
        echo "Unknown CNI: ${CNI}. Use 'cilium' or 'calico'"
        exit 1
        ;;
esac

kubectl get nodes
