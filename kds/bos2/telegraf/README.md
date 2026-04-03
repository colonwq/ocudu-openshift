# Telegraf metrics for ocudu-gnb (OpenShift)

This directory deploys [Telegraf](https://www.influxdata.com/time-series-platform/telegraf/) into the **`ocudu`** namespace so **gNB metrics** (JSON over WebSocket, via the ocudu custom image) are converted to **Prometheus exposition format** and scraped by **OpenShift cluster monitoring**.

The Telegraf image is built from [colonwq/ocudu `docker/telegraf`](https://github.com/colonwq/ocudu/tree/dev/docker/telegraf) (entrypoint, `ws_adapter.py`, and bundled configs). The manifests here pin **`quay.io/kschinck/telegraf:20260402d01`** and override the main config with a Kubernetes ConfigMap.

## End-to-end flow

1. **gNB** exposes **remote_control** on **port 8001** (WebSocket metrics subscription). This matches `remote_control` in [`../ocudu/40-values-override.yaml`](../ocudu/40-values-override.yaml).
2. A **Service** selects the gNB pod (`app.kubernetes.io/name=ocudu-gnb`) and forwards cluster DNS traffic to **8001**.
3. **Telegraf** runs with **`WS_URL`** set to that Service’s host/port. **`ws_adapter.py`** opens `ws://…`, sends `metrics_subscribe`, and prints JSON lines for Telegraf’s **execd** + **xpath_json** parsers.
4. Telegraf’s **`prometheus_client`** output listens on **9273** and serves **`/metrics`**.
5. A **ServiceMonitor** tells **User Workload Monitoring** Prometheus to scrape **`http://ocudu-telegraf:9273/metrics`** (not `prometheus-k8s`; see below).

Prometheus does **not** scrape the gNB directly; it scrapes **Telegraf**, which is the bridge from WebSocket JSON to Prometheus text format.

### Which Prometheus scrapes `ocudu`?

**`prometheus-k8s-0`** in **`openshift-monitoring`** is **platform** monitoring (cluster control plane, etc.). It **does not** scrape arbitrary `ServiceMonitors` in **`ocudu`**.

You need **User Workload Monitoring (UWM)** enabled so **`prometheus-user-workload-*`** in **`openshift-user-workload-monitoring`** runs and scrapes user namespaces. If `oc get prometheus -A` only lists **`k8s`** under **`openshift-monitoring`** and there is **no** `openshift-user-workload-monitoring` namespace, apply **`05-cluster-monitoring-config-enable-uwm.yaml`** once (cluster-admin), wait for the new Prometheus pods, then confirm targets and **Observe → Metrics** using queries like `up{namespace="ocudu"}`.

## Prerequisites

- Namespace **`ocudu`** exists (e.g. [`../ocudu/00-install-ocudu.sh`](../ocudu/00-install-ocudu.sh)).
- **Helm release `ocudu-gnb`** is running with gNB pods labeled **`app.kubernetes.io/name=ocudu-gnb`** (same label as [`../ocudu/50-wait-for-ocudu.sh`](../ocudu/50-wait-for-ocudu.sh)).
- Cluster has the **monitoring.coreos.com** API (Prometheus Operator / OpenShift monitoring).

## Scripts

### `00-install-telegraf.sh`

Main installer. It:

1. **`oc apply -f 05-cluster-monitoring-config-enable-uwm.yaml`** if **`cluster-monitoring-config`** is not already present in **`openshift-monitoring`** (enables UWM without overwriting an existing **`config.yaml`**).

2. **`oc label namespace ocudu openshift.io/cluster-monitoring=true --overwrite`** for user workload monitoring discovery.

3. **`oc apply`** of the remaining YAML files: gNB Service → ConfigMap → Deployment → Telegraf Service → ServiceMonitor.

4. Runs **`./60-wait-for-telegraf.sh`** to wait for the Deployment rollout and a Ready pod.

### `60-wait-for-telegraf.sh`

Waits for **`deployment/ocudu-telegraf`** to finish rolling out, then **`oc wait`** for a Ready pod with label **`app.kubernetes.io/name=ocudu-telegraf`**. On failure, prints recent pod logs.

### `99-uninstall-telegraf.sh`

Deletes the objects created from the YAML files (ServiceMonitor, Services, Deployment, ConfigMap), in an order safe for Kubernetes references. It does **not** remove the **`openshift.io/cluster-monitoring`** label from `ocudu` automatically; the script prints the optional `oc label … -` command if you want to remove it and nothing else in that namespace needs cluster monitoring.

## YAML manifests (apply order)

| File | Kind | What it does |
|------|------|----------------|
| `10-ocudu-gnb-remote-control-svc.yaml` | `Service` | **`ocudu-gnb-remote-control`** in `ocudu`: ClusterIP to gNB pods on **8001** (`remote_control` / WebSocket). |
| `20-telegraf-configmap.yaml` | `ConfigMap` **`ocudu-telegraf`** | **`telegraf.conf`**: same **inputs** pattern as upstream ocudu Telegraf (execd + xpath for UE/cell/OFH/CU-CP, etc.), but **outputs** are only **`prometheus_client`** on **9273** (no **`health`** output: it would also bind **9273** and conflict). No InfluxDB on-cluster. |
| `30-telegraf-deployment.yaml` | `Deployment` **`ocudu-telegraf`** | Runs the Telegraf container, sets **`WS_URL`** to the gNB Service above, mounts the ConfigMap over **`/etc/ocudu/telegraf.conf`**, sets **`TELEGRAF_CLI_EXTRA_ARGS=--output-filter prometheus_client`** so only the Prometheus output runs (ignores **`[[outputs.health]]`** if the image default config is still used), exposes **9273**, probes **`/metrics`**. If you enable **`PROMETHEUS_REMOTE_WRITE_URL`**, change the filter to **`prometheus_client:http`**. |
| `40-telegraf-service.yaml` | `Service` **`ocudu-telegraf`** | ClusterIP **9273** → Telegraf pod (`metrics` port). |
| `50-servicemonitor.yaml` | `ServiceMonitor` **`ocudu-telegraf`** | Scrape **`/metrics`** on port **`metrics`** every **30s**. Label **`openshift.io/cluster-monitoring: "true"`** aligns with how the monitoring operator selects user workload targets together with the namespace label. |
| `05-cluster-monitoring-config-enable-uwm.yaml` | `ConfigMap` **`cluster-monitoring-config`** | **Optional, cluster-wide (cluster-admin):** sets **`enableUserWorkload: true`** so **`openshift-user-workload-monitoring`** and **`prometheus-user-workload-*`** exist. **Do not** overwrite an existing `cluster-monitoring-config` without merging into its `config.yaml`. |

## OpenShift Prometheus notes

- **Namespace `ocudu`**: `00-install-telegraf.sh` sets **`openshift.io/cluster-monitoring=true`** so user workload collection can include this project (required pattern for user-defined metrics in supported configurations).
- **UWM**: For metrics to appear in **Observe → Metrics** and in **`up{namespace="ocudu"}`**, **User Workload Monitoring** must be enabled (see **`05-cluster-monitoring-config-enable-uwm.yaml`**). Checking **`prometheus-k8s-0`** targets for **`ocudu`** will stay empty; use **`prometheus-user-workload-0`** in **`openshift-user-workload-monitoring`** after UWM is ready.

## Optional: Prometheus remote_write

The image entrypoint loads **`/etc/ocudu/telegraf-ocp-remote-write.conf`** when **`PROMETHEUS_REMOTE_WRITE_URL`** is non-empty (see upstream [telegraf-ocp-remote-write.conf](https://github.com/colonwq/ocudu/blob/dev/docker/telegraf/telegraf-ocp-remote-write.conf)). You can add that environment variable to **`30-telegraf-deployment.yaml`** (or patch the Deployment) to push metrics to a remote-write receiver (e.g. Thanos receive, Mimir). Many in-cluster endpoints require **TLS** and a **bearer token**; wire those via Secrets and extra env or a custom config fragment as needed.

## Quick start

```bash
cd kds/bos2/telegraf
./00-install-telegraf.sh
```

**`00-install-telegraf.sh`** applies **`05-cluster-monitoring-config-enable-uwm.yaml`** when **`cluster-monitoring-config`** is **missing** in **`openshift-monitoring`** (cluster-admin). If that ConfigMap **already exists**, the script skips the file so it does not replace your **`config.yaml`**; merge **`enableUserWorkload: true`** yourself if UWM is not on yet. After the first UWM enable, wait until **`oc get pods -n openshift-user-workload-monitoring`** shows **Ready** Prometheus pods before expecting **Observe → Metrics** to show **`ocudu`**.

To remove this stack (keeping the `ocudu` namespace and gNB):

```bash
./99-uninstall-telegraf.sh
```
