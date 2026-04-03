#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

oc delete -f 50-servicemonitor.yaml --ignore-not-found
oc delete -f 40-telegraf-service.yaml --ignore-not-found
oc delete -f 30-telegraf-deployment.yaml --ignore-not-found
oc delete -f 20-telegraf-configmap.yaml --ignore-not-found
oc delete -f 10-ocudu-gnb-remote-control-svc.yaml --ignore-not-found

echo "Optional: remove UWM label from ocudu if nothing else in the namespace should be user-monitored:"
echo "  oc label namespace ocudu openshift.io/user-monitoring-"
