#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="mtls-test"

echo "Enrolling namespace ${NAMESPACE} in ztunnel mTLS..."

kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "${NAMESPACE}" io.cilium/mtls-enabled=true --overwrite

echo "Waiting for enrollment (5s)..."
sleep 5

echo "Namespace ${NAMESPACE} enrolled"
kubectl get namespace "${NAMESPACE}" --show-labels
