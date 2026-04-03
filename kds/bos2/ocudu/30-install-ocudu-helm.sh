#!/bin/bash
# Install ocudu-gnb from a local chart tarball (avoids repeated OCI pulls / rate limits).
# If ocudu-gnb-<version>.tgz is missing, helm pull downloads it into this directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CHART_VERSION="3.2.0"
OCI_URL="oci://registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/ocudu-gnb"
CHART_TGZ="${SCRIPT_DIR}/ocudu-gnb-${CHART_VERSION}.tgz"

# Platform-to-image-tag mapping (from 00-install-ocudu.sh -p argument)
get_image_tag() {
  case "$1" in
    f) echo "20260401f01" ;;
    c) echo "20260401c01" ;;
    u) echo "20260306u01" ;;
    r) echo "20260401r01" ;;
    *) echo "20260401f01" ;;  # default
  esac
}

PLATFORM="${1:-f}"
IMAGE_TAG=$(get_image_tag "$PLATFORM")

if [[ ! -f "$CHART_TGZ" ]]; then
  echo "${CHART_TGZ##*/} not found; pulling chart with helm"
  helm pull "$OCI_URL" --version "$CHART_VERSION" --destination "$SCRIPT_DIR"
fi

if [[ ! -f "$CHART_TGZ" ]]; then
  echo "ERROR: expected chart archive at $CHART_TGZ after helm pull"
  echo "Check helm pull output; OCI may name the file differently."
  exit 1
fi

helm install ocudu-gnb "$CHART_TGZ" \
  -f 40-values-override.yaml \
  --set image.tag="$IMAGE_TAG" \
  -n ocudu
