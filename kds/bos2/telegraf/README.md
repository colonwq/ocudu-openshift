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

2. **`oc label namespace ocudu openshift.io/user-monitoring=true --overwrite`** and **removes** **`openshift.io/cluster-monitoring`** if present (that label **excludes** the namespace from user-workload Prometheus; see OpenShift `user-workload` Prometheus **`serviceMonitorNamespaceSelector`**).

3. **`oc apply`** of the remaining YAML files: gNB Service → ConfigMap → Deployment → Telegraf Service → ServiceMonitor.

4. Runs **`./60-wait-for-telegraf.sh`** to wait for the Deployment rollout and a Ready pod.

### `60-wait-for-telegraf.sh`

Waits for **`deployment/ocudu-telegraf`** to finish rolling out, then **`oc wait`** for a Ready pod with label **`app.kubernetes.io/name=ocudu-telegraf`**. On failure, prints recent pod logs.

### `99-uninstall-telegraf.sh`

Deletes the objects created from the YAML files (ServiceMonitor, Services, Deployment, ConfigMap), in an order safe for Kubernetes references. It does **not** remove **`openshift.io/user-monitoring`** from `ocudu` automatically; the script prints the optional `oc label … -` command if you want to remove it.

## YAML manifests (apply order)

| File | Kind | What it does |
|------|------|----------------|
| `10-ocudu-gnb-remote-control-svc.yaml` | `Service` | **`ocudu-gnb-remote-control`** in `ocudu`: ClusterIP to gNB pods on **8001** (`remote_control` / WebSocket). |
| `20-telegraf-configmap.yaml` | `ConfigMap` **`ocudu-telegraf`** | **`telegraf.conf`**: same **inputs** pattern as upstream ocudu Telegraf (execd + xpath for UE/cell/OFH/CU-CP, etc.), but **outputs** are only **`prometheus_client`** on **9273** (no **`health`** output: it would also bind **9273** and conflict). No InfluxDB on-cluster. |
| `30-telegraf-deployment.yaml` | `Deployment` **`ocudu-telegraf`** | Runs the Telegraf container, sets **`WS_URL`** to the gNB Service above, mounts the ConfigMap over **`/etc/ocudu/telegraf.conf`**, sets **`TELEGRAF_CLI_EXTRA_ARGS=--output-filter prometheus_client`** so only the Prometheus output runs (ignores **`[[outputs.health]]`** if the image default config is still used), exposes **9273**, probes **`/metrics`**. If you enable **`PROMETHEUS_REMOTE_WRITE_URL`**, change the filter to **`prometheus_client:http`**. |
| `40-telegraf-service.yaml` | `Service` **`ocudu-telegraf`** | ClusterIP **9273** → Telegraf pod (`metrics` port). |
| `50-servicemonitor.yaml` | `ServiceMonitor` **`ocudu-telegraf`** | Scrape **`/metrics`** on port **`metrics`** every **30s**. Label **`openshift.io/user-monitoring: "true"`** matches UWM expectations; namespace must **not** use **`openshift.io/cluster-monitoring=true`** or UWM ignores the project. |
| `05-cluster-monitoring-config-enable-uwm.yaml` | `ConfigMap` **`cluster-monitoring-config`** | **Optional, cluster-wide (cluster-admin):** sets **`enableUserWorkload: true`** so **`openshift-user-workload-monitoring`** and **`prometheus-user-workload-*`** exist. **Do not** overwrite an existing `cluster-monitoring-config` without merging into its `config.yaml`. |

## OpenShift Prometheus notes

- **Namespace `ocudu`**: must be eligible for **User Workload Monitoring**. `00-install-telegraf.sh` sets **`openshift.io/user-monitoring=true`**. The **`openshift.io/cluster-monitoring=true`** label **must not** be set on `ocudu`: the **`user-workload`** Prometheus **`serviceMonitorNamespaceSelector`** excludes namespaces where that label is **`true`** (see [cluster-monitoring-operator](https://github.com/openshift/cluster-monitoring-operator) `assets/prometheus-user-workload/prometheus.yaml`).
- **UWM**: For metrics in **Observe → Metrics** and **`up{namespace="ocudu"}`**, enable UWM (**`05-cluster-monitoring-config-enable-uwm.yaml`**). Inspect targets on **`prometheus-user-workload-0`**, not **`prometheus-k8s-0`**.

## How to verify telegraf is reporting

Check **User Workload Monitoring** Prometheus, not **`prometheus-k8s`**: **`openshift-monitoring`** does not scrape the **`ocudu`** `ServiceMonitor`.

**1. Scrape target health** — expect **`"up"`** for the Telegraf job in **`ocudu`**:

```bash
oc exec -n openshift-user-workload-monitoring prometheus-user-workload-0 -c prometheus -- \
  curl -sG 'http://127.0.0.1:9090/api/v1/targets' \
  | jq '.data.activeTargets[] | select(.labels.namespace=="ocudu") | .health'
```

Example output:

```text
"up"
```

For more detail (URL, last error), print the whole selected object:

```bash
oc exec -n openshift-user-workload-monitoring prometheus-user-workload-0 -c prometheus -- \
  curl -sG 'http://127.0.0.1:9090/api/v1/targets' \
  | jq '.data.activeTargets[] | select(.labels.namespace=="ocudu")'
```

**2. Console** — **Observe → Metrics** → run:

```promql
up{namespace="ocudu"}
```

When scraping works, the value is **`1`**.

If the target is **down** or **`up`** is **`0`**, confirm **`openshift.io/user-monitoring=true`** on **`ocudu`**, that **`openshift.io/cluster-monitoring`** is **not** set on **`ocudu`**, and that Telegraf serves metrics: **`curl -s http://ocudu-telegraf.ocudu.svc:9273/metrics`** from a pod in **`ocudu`**.

## How to query and report data

After verification (**How to verify telegraf is reporting**), use the options below to list metric names, inspect values, and explore series.

All **`oc exec … prometheus-user-workload-0`** examples assume the UWM pod name **`prometheus-user-workload-0`** in **`openshift-user-workload-monitoring`** (adjust if your cluster uses a different ordinal).

### List metric names (`__name__`) in `ocudu`

Prometheus HTTP API: label values for **`__name__`**, restricted to series in **`ocudu`**:

```bash
oc exec -n openshift-user-workload-monitoring prometheus-user-workload-0 -c prometheus -- \
  sh -c "curl -sG 'http://127.0.0.1:9090/api/v1/label/__name__/values' \
  --data-urlencode 'match[]={namespace=\"ocudu\"}'" | jq -r '.data[]' | sort -u
```

### Query a specific metric (instant vector)

Replace the metric name with one from the list above (Telegraf often exposes names such as **`cell_*`** from the gNB JSON pipeline):

```bash
oc exec -n openshift-user-workload-monitoring prometheus-user-workload-0 -c prometheus -- \
  curl -sG 'http://127.0.0.1:9090/api/v1/query' \
  --data-urlencode 'query=cell_average_latency{namespace="ocudu"}' | jq .
```

Use **`/api/v1/query_range`** with **`start`**, **`end`**, and **`step`** parameters when you need a time range.

### OpenShift console (**Observe → Metrics**)

Run PromQL scoped to the namespace, for example:

```promql
{namespace="ocudu"}
```

Or narrow by name pattern:

```promql
{namespace="ocudu", __name__=~"cell_.*"}
```

Use the UI’s metric picker or autocomplete where available (behavior depends on console version and whether queries go through Thanos).

### PromQL aggregations

Count series by scrape **`job`**:

```promql
count by (job) ({namespace="ocudu"})
```

See which metric names contribute the most series (useful when cardinality is manageable):

```promql
topk(20, count by (__name__) ({namespace="ocudu"}))
```

### List series and full label sets

**`/api/v1/series`** returns matching series with all labels; the result can be large. Example capped at 20 entries in **`jq`**:

```bash
oc exec -n openshift-user-workload-monitoring prometheus-user-workload-0 -c prometheus -- \
  sh -c "curl -sG 'http://127.0.0.1:9090/api/v1/series' \
  --data-urlencode 'match[]={namespace=\"ocudu\"}'" | jq '.data[:20]'
```

### Direct check from Telegraf (bypass Prometheus)

To confirm exposition before or independently of scraping:

```bash
oc run curl-tg --rm -i --restart=Never -n ocudu --image=curlimages/curl -- \
  curl -s http://ocudu-telegraf.ocudu.svc:9273/metrics | head
```

## Available metrics

These **`__name__`** values are typical of the **cell** and **DU MAC** measurements Telegraf exposes after parsing gNB JSON (see **`20-telegraf-configmap.yaml`** **`[[inputs.execd.xpath]]`** for **`cell`** and related paths). Your live set can differ with gNB version, config, or load; use [**How to query and report data**](#how-to-query-and-report-data) to list names from Prometheus.

| Metric | Area |
|--------|------|
| `cell_average_latency` | Cell |
| `cell_avg_prach_delay` | Cell |
| `cell_error_indication_count` | Cell |
| `cell_late_dl_harqs` | Cell |
| `cell_late_ul_harqs` | Cell |
| `cell_latency_histogram_0` | Cell (latency histogram bucket) |
| `cell_latency_histogram_1` | Cell (latency histogram bucket) |
| `cell_latency_histogram_2` | Cell (latency histogram bucket) |
| `cell_latency_histogram_3` | Cell (latency histogram bucket) |
| `cell_latency_histogram_4` | Cell (latency histogram bucket) |
| `cell_latency_histogram_5` | Cell (latency histogram bucket) |
| `cell_latency_histogram_6` | Cell (latency histogram bucket) |
| `cell_latency_histogram_7` | Cell (latency histogram bucket) |
| `cell_latency_histogram_8` | Cell (latency histogram bucket) |
| `cell_latency_histogram_9` | Cell (latency histogram bucket) |
| `cell_max_latency` | Cell |
| `cell_msg3_nof_nok` | Cell |
| `cell_msg3_nof_ok` | Cell |
| `cell_nof_failed_pdcch_allocs` | Cell |
| `cell_nof_failed_uci_allocs` | Cell |
| `cell_pci` | Cell |
| `cell_pdsch_prbs_used_per_tdd_slot_idx_0` | Cell (PDSCH PRBs per TDD slot index) |
| `cell_pdsch_prbs_used_per_tdd_slot_idx_1` | Cell (PDSCH PRBs per TDD slot index) |
| `cell_pdsch_prbs_used_per_tdd_slot_idx_2` | Cell (PDSCH PRBs per TDD slot index) |
| `cell_pdsch_prbs_used_per_tdd_slot_idx_3` | Cell (PDSCH PRBs per TDD slot index) |
| `cell_pdsch_prbs_used_per_tdd_slot_idx_4` | Cell (PDSCH PRBs per TDD slot index) |
| `cell_pdsch_prbs_used_per_tdd_slot_idx_5` | Cell (PDSCH PRBs per TDD slot index) |
| `cell_pdsch_prbs_used_per_tdd_slot_idx_6` | Cell (PDSCH PRBs per TDD slot index) |
| `cell_pdsch_prbs_used_per_tdd_slot_idx_7` | Cell (PDSCH PRBs per TDD slot index) |
| `cell_pdsch_prbs_used_per_tdd_slot_idx_8` | Cell (PDSCH PRBs per TDD slot index) |
| `cell_pdsch_prbs_used_per_tdd_slot_idx_9` | Cell (PDSCH PRBs per TDD slot index) |
| `cell_pucch_tot_rb_usage_avg` | Cell |
| `cell_pusch_prbs_used_per_tdd_slot_idx_0` | Cell (PUSCH PRBs per TDD slot index) |
| `cell_pusch_prbs_used_per_tdd_slot_idx_1` | Cell (PUSCH PRBs per TDD slot index) |
| `cell_pusch_prbs_used_per_tdd_slot_idx_2` | Cell (PUSCH PRBs per TDD slot index) |
| `cell_pusch_prbs_used_per_tdd_slot_idx_3` | Cell (PUSCH PRBs per TDD slot index) |
| `cell_pusch_prbs_used_per_tdd_slot_idx_4` | Cell (PUSCH PRBs per TDD slot index) |
| `cell_pusch_prbs_used_per_tdd_slot_idx_5` | Cell (PUSCH PRBs per TDD slot index) |
| `cell_pusch_prbs_used_per_tdd_slot_idx_6` | Cell (PUSCH PRBs per TDD slot index) |
| `cell_pusch_prbs_used_per_tdd_slot_idx_7` | Cell (PUSCH PRBs per TDD slot index) |
| `cell_pusch_prbs_used_per_tdd_slot_idx_8` | Cell (PUSCH PRBs per TDD slot index) |
| `cell_pusch_prbs_used_per_tdd_slot_idx_9` | Cell (PUSCH PRBs per TDD slot index) |
| `du_du_high_mac_dl_0_average_latency_us` | DU (MAC DL) |
| `du_du_high_mac_dl_0_cpu_usage_percent` | DU (MAC DL) |
| `du_du_high_mac_dl_0_max_latency_us` | DU (MAC DL) |
| `du_du_high_mac_dl_0_min_latency_us` | DU (MAC DL) |
| `du_du_high_mac_dl_1_pci` | DU (MAC DL) |

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
