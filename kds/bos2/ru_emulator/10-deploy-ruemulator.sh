#!/bin/bash
# Install ru-emulator from a local chart tarball (avoids repeated OCI pulls / rate limits).
# If ru-emulator-<version>.tgz is missing, helm pull downloads it into this directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CHART_VERSION="2.0.0-dev"
OCI_URL="oci://registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/ru-emulator"
CHART_TGZ="${SCRIPT_DIR}/ru-emulator-${CHART_VERSION}.tgz"

if [[ ! -f "$CHART_TGZ" ]]; then
  echo "${CHART_TGZ##*/} not found; pulling chart with helm"
  helm pull "$OCI_URL" --version "$CHART_VERSION" --destination "$SCRIPT_DIR"
fi

if [[ ! -f "$CHART_TGZ" ]]; then
  echo "ERROR: expected chart archive at $CHART_TGZ after helm pull"
  echo "Check helm pull output; OCI may name the file differently."
  exit 1
fi

helm install ru-emulator "$CHART_TGZ" -f ./values.yaml -n ocudu
