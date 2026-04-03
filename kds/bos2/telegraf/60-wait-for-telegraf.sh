#!/bin/bash
set -euo pipefail

NAMESPACE="ocudu"
LABEL="app.kubernetes.io/name=ocudu-telegraf"
TIMEOUT="180s"

echo "Waiting for Telegraf deployment in $NAMESPACE..."
oc rollout status deployment/ocudu-telegraf -n "$NAMESPACE" --timeout="$TIMEOUT"

if oc wait --for=condition=Ready pod -l "$LABEL" -n "$NAMESPACE" --timeout=60s; then
  echo "Telegraf pod is Ready."
  oc get pods -n "$NAMESPACE" -l "$LABEL"
else
  echo "Telegraf pod did not become Ready."
  oc get pods -n "$NAMESPACE" -l "$LABEL" || true
  oc logs -n "$NAMESPACE" -l "$LABEL" --tail=80 || true
  exit 1
fi
