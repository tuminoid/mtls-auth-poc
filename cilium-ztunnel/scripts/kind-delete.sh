#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-mtls-poc}"

if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    echo "Deleting Kind cluster: ${CLUSTER_NAME}"
    kind delete cluster --name "${CLUSTER_NAME}"
    echo "Cluster deleted"
else
    echo "Cluster ${CLUSTER_NAME} does not exist"
fi
