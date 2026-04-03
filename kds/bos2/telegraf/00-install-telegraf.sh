#!/bin/bash
# Deploy Telegraf in ocudu: collects gNB JSON metrics over WebSocket (ws_adapter) and
# exposes Prometheus format on :9273 for OpenShift monitoring to scrape.
#
# Prerequisites:
#   - Namespace ocudu exists (ocudu/00-install-ocudu.sh).
#   - gNB pod is labeled app.kubernetes.io/name=ocudu-gnb with remote_control on port 8001
#     (see ocudu 40-values-override.yaml).
#
# OpenShift Prometheus integration:
#   - This bundle labels namespace ocudu with openshift.io/cluster-monitoring=true so the
#     platform monitoring stack can discover ServiceMonitors there (typical SNO / lab).
#   - If you rely on User Workload Monitoring only, enable enableUserWorkload in
#     openshift-monitoring/cluster-monitoring-config and ensure your UWM Prometheus
#     discovers ServiceMonitors in ocudu (often the default when UWM is enabled).
#
# Optional remote_write (same as colonwq/ocudu image entrypoint): set
#   PROMETHEUS_REMOTE_WRITE_URL in 40-telegraf-deployment.yaml or patch the Deployment.
#   The image loads /etc/ocudu/telegraf-ocp-remote-write.conf when that variable is set.
#   Many in-cluster receivers need TLS and a bearer token; configure accordingly.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Labeling namespace ocudu for cluster monitoring (ServiceMonitor discovery)"
oc label namespace ocudu openshift.io/cluster-monitoring=true --overwrite

echo "Applying gNB remote-control Service (port 8001) for Telegraf WebSocket"
oc apply -f 10-ocudu-gnb-remote-control-svc.yaml

echo "Applying Telegraf ConfigMap, workload, Service, and ServiceMonitor"
oc apply -f 20-telegraf-configmap.yaml
oc apply -f 30-telegraf-deployment.yaml
oc apply -f 40-telegraf-service.yaml
oc apply -f 50-servicemonitor.yaml

echo "Waiting for Telegraf rollout"
./60-wait-for-telegraf.sh

echo "Done. Query metrics from the telegraf Service (port 9273) or use OpenShift Observe → Metrics."
echo "Example: oc run curl-tg --rm -i --restart=Never -n ocudu --image=curlimages/curl -- curl -s http://ocudu-telegraf.ocudu.svc:9273/metrics | head"
