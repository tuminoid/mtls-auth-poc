#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Deploying iptables interception..."

kubectl apply -f "${REPO_ROOT}/manifests/iptables-interception.yaml"

echo "Waiting for iptables DaemonSet..."
kubectl -n envoy-system rollout status daemonset/iptables-interception --timeout=120s

echo "iptables interception deployed"
kubectl -n envoy-system get pods -l app=iptables-interception -o wide
