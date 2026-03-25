#!/bin/bash

usage() {
  echo "Usage: $0 [-p platform]"
  echo "  -p platform   OS platform for the image (optional, default: fedora)"
  echo "                f|fedora, c|centos, r|redhat, u|ubuntu"
  exit 1
}

validate_platform() {
  case "${1,,}" in
    f|fedora)  echo "f" ;;
    c|centos)  echo "c" ;;
    r|redhat)  echo "r" ;;
    u|ubuntu)  echo "u" ;;
    *)         echo "" ;;
  esac
}

PLATFORM="f"
P_GIVEN=0
while getopts "p:h" opt; do
  case $opt in
    p) P_GIVEN=1; INVALID_OPTARG="$OPTARG"; PLATFORM=$(validate_platform "$OPTARG") ;;
    h) usage ;;
    *) usage ;;
  esac
done

if [[ $P_GIVEN -eq 1 && -z "$PLATFORM" ]]; then
  echo "Error: invalid platform '$INVALID_OPTARG'. Valid options: f|fedora, c|centos, r|redhat, u|ubuntu"
  exit 1
fi

echo "Creating the ocudu namespace"
oc apply -f 10-ocudu-ns.yaml

echo "Applying SCC"
oc apply -f 20-ocudu-scc.yaml

echo "Installing ocudu helm chart (platform: $PLATFORM)"
./30-install-ocudu-helm.sh "$PLATFORM"

echo "Waiting for ocudu to be running"
./50-wait-for-ocudu.sh
