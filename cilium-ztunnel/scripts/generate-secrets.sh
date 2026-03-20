#!/usr/bin/env bash
set -euo pipefail

# Generate bootstrap and CA secrets required by Cilium ztunnel.
# Bootstrap keys secure the ztunnel <-> Cilium xDS connection.
# CA keys are the root for ephemeral client certificates.

TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT

echo "Generating ztunnel secrets..."

# Bootstrap keypair
openssl genrsa -out "${TMPDIR}/bootstrap-private.key" 2048 2>/dev/null

cat > "${TMPDIR}/bootstrap.conf" <<CONF
[ req ]
distinguished_name = req_distinguished_name
x509_extensions = v3_ext
prompt = no

[ req_distinguished_name ]
O = cluster.local

[ v3_ext ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
CONF

openssl req -x509 -new -nodes \
    -key "${TMPDIR}/bootstrap-private.key" \
    -sha256 -days 3650 \
    -out "${TMPDIR}/bootstrap-root.crt" \
    -config "${TMPDIR}/bootstrap.conf" 2>/dev/null

# CA keypair
openssl genrsa -out "${TMPDIR}/ca-private.key" 2048 2>/dev/null

cat > "${TMPDIR}/ca.conf" <<CONF
[ req ]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no

[ req_distinguished_name ]
O = cluster.local

[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
CONF

openssl req -x509 -new -nodes \
    -key "${TMPDIR}/ca-private.key" \
    -sha256 -days 3650 \
    -out "${TMPDIR}/ca-root.crt" \
    -config "${TMPDIR}/ca.conf" 2>/dev/null

# Create Kubernetes secret
kubectl -n kube-system delete secret cilium-ztunnel-secrets --ignore-not-found
kubectl -n kube-system create secret generic cilium-ztunnel-secrets \
    --from-file=bootstrap-private.key="${TMPDIR}/bootstrap-private.key" \
    --from-file=bootstrap-root.crt="${TMPDIR}/bootstrap-root.crt" \
    --from-file=ca-private.key="${TMPDIR}/ca-private.key" \
    --from-file=ca-root.crt="${TMPDIR}/ca-root.crt"

echo "Secret cilium-ztunnel-secrets created in kube-system"
