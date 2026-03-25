#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CHART_TGZ="${SCRIPT_DIR}/open5gs-2.2.5.tgz"
OCI_URL="oci://registry-1.docker.io/gradiant/open5gs"
CHART_VERSION="2.2.5"

#deploy open5gs from docker
#helm install open5gs oci://registry-1.docker.io/gradiant/open5gs --version 2.2.5 -f 5gSA-values.yaml -f override-values.yaml -n open5gs

if [[ ! -f "$CHART_TGZ" ]]; then
  echo "open5gs-2.2.5.tgz not found; pulling chart with helm"
  helm pull "$OCI_URL" --version "$CHART_VERSION" --destination "$SCRIPT_DIR"
fi

#install open5gs from a local copy. Damn rate limiting
helm install open5gs "$CHART_TGZ" \
  -f 5gSA-values.yaml \
  -f override-values.yaml \
  -n open5gs
