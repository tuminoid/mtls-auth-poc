#!/usr/bin/env bash

set -euo pipefail

IS_CONTAINER="${IS_CONTAINER:-false}"
CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-docker}"
WORKDIR="${WORKDIR:-/workdir}"

# Shellcheck options:
# -s bash: Check for bash
# -o all: Enable all optional checks
SHELLCHECK_OPTS="-s bash -o all"

if [[ "${IS_CONTAINER}" != "false" ]]; then
    TOP_DIR="${1:-.}"
    # shellcheck disable=SC2086
    find "${TOP_DIR}" -name '*.sh' -type f -exec shellcheck ${SHELLCHECK_OPTS} {} \+
else
    "${CONTAINER_RUNTIME}" run --rm \
        --env IS_CONTAINER=TRUE \
        --volume "${PWD}:${WORKDIR}:ro,z" \
        --entrypoint sh \
        --workdir "${WORKDIR}" \
        docker.io/koalaman/shellcheck-alpine:v0.11.0@sha256:9955be09ea7f0dbf7ae942ac1f2094355bb30d96fffba0ec09f5432207544002 \
        "${WORKDIR}/hack/shellcheck.sh" "$@"
fi
