#!/bin/bash
# Merge cluster pull-secret with local Podman auth (e.g. docker.io), apply to openshift-config,
# wait 30s, then wait until MachineConfigPool master reports Updated=True.
#
# Requires: oc, jq, podman (podman login used if docker.io is missing from auth.json)
# Usage: ./92-merge-pull-secret-wait-mcp.sh
# Run from any directory (uses paths relative to this script for temp files).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="${TMPDIR:-/tmp}"
CLUSTER_PULL="$(mktemp -p "$TMP_DIR" cluster-pull-secret.XXXXXX)"
COMBINED="$(mktemp -p "$TMP_DIR" combined-pull-secret.XXXXXX)"
PODMAN_AUTH="${PODMAN_AUTH:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/containers/auth.json}"

cleanup() {
  rm -f "$CLUSTER_PULL" "$COMBINED"
}
trap cleanup EXIT

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: '$1' not found in PATH" >&2
    exit 1
  }
}

need_cmd oc
need_cmd jq
need_cmd podman

ensure_docker_io_in_podman_auth() {
  mkdir -p "$(dirname "$PODMAN_AUTH")"
  if [[ ! -f "$PODMAN_AUTH" ]] || [[ ! -s "$PODMAN_AUTH" ]]; then
    echo '{}' > "$PODMAN_AUTH"
  fi
  if ! jq -e '.auths["docker.io"]? // .auths["https://index.docker.io/v1/"]?' "$PODMAN_AUTH" >/dev/null 2>&1; then
    echo "No docker.io credentials in $PODMAN_AUTH — run podman login docker.io"
    podman login docker.io
  else
    echo "docker.io auth already present in $PODMAN_AUTH"
  fi
}

echo "Exporting cluster pull-secret..."
oc get secret/pull-secret -n openshift-config \
  --template='{{index .data ".dockerconfigjson" | base64decode}}' > "$CLUSTER_PULL"

ensure_docker_io_in_podman_auth

echo "Merging cluster pull-secret with Podman auth..."
jq -s '.[0] * .[1]' "$CLUSTER_PULL" "$PODMAN_AUTH" > "$COMBINED"

echo "Updating openshift-config/pull-secret..."
oc set data secret/pull-secret -n openshift-config \
  --from-file=.dockerconfigjson="$COMBINED"

echo "Waiting 30 seconds before checking MachineConfigPool..."
sleep 30

echo "Waiting for MachineConfigPool master Updated=True..."
until oc wait mcp master --for='condition=Updated=True' --timeout=10s &>/dev/null; do
  echo "  Master pool still updating... $(date -Is)"
  sleep 15
done
echo "Master MachineConfigPool is Updated."
