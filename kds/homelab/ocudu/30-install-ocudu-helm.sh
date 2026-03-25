#!/bin/bash

# Platform-to-image-tag mapping (from 00-install-ocudu.sh -p argument)
get_image_tag() {
  case "$1" in
    f) echo "20260306f01" ;;
    c) echo "20260306c03" ;;
    u) echo "20260306u01" ;;
    r) echo "20260309r01" ;;
    *) echo "20260306f01" ;;  # default
  esac
}

PLATFORM="${1:-f}"
IMAGE_TAG=$(get_image_tag "$PLATFORM")

helm install ocudu-gnb oci://registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/ocudu-gnb --version 3.2.0 -f 40-values-override.yaml --set image.tag="$IMAGE_TAG" -n ocudu

