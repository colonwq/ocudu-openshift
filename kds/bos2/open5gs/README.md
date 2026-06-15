# open5gs deployment (OpenShift)

This directory deploys **Open5GS** (5G SA core and related components) via the **Gradiant** Helm chart into the **`open5gs`** namespace. It is the control-plane / core side of the **`kds/bos2`** lab stack used with **ocudu-gnb** and **ru_emulator**.

Chart OCI: **`registry-1.docker.io/gradiant/open5gs`**, version **2.2.5** (local **`open5gs-2.2.5.tgz`** pulled if missing).

## Files

| File | Role |
|------|------|
| **`00-install-open5gs.sh`** | Full install pipeline: namespace → PVC → Helm → SCC patch → webgui init patch → Route → rollout wait → default subscriber. |
| **`20-open5gs-ns.yaml`** | **`Project`** **`open5gs`** (OpenShift project / namespace). |
| **`30-mongo-pvc.yaml`** | **PersistentVolumeClaim** for MongoDB used by the chart. |
| **`35-deploy-open5gs.sh`** | **`helm install open5gs`** using **`5gSA-values.yaml`** and **`override-values.yaml`**. |
| **`5gSA-values.yaml`** | Base 5G SA Helm values for the chart. |
| **`override-values.yaml`** | Local overrides (images, resources, toggles) layered on **`5gSA-values.yaml`**. |
| **`override.yaml`** | Extra overrides kept in-repo (use depends on whether **`35-deploy-open5gs.sh`** references it; current script uses **`override-values.yaml`** only). |
| **`36-update-open5gs-scc.yaml`** | SCC-related updates so chart workloads can run under OpenShift constraints. |
| **`37-update-webgui-init.yaml`** | Patches **webgui** deployment so the init container can start as required on OCP. |
| **`40-webgui-route.yaml`** | **OpenShift Route** to **`open5gs-webui`** service (port **9999**); host auto-generated if unset. |
| **`50-rollout-wait.sh`** | **`oc rollout status`** for every **Deployment** in **`open5gs`** (300s timeout each). |
| **`60-add-subscriber.sh`** | Inserts a default subscriber document into MongoDB (**IMSI `999700000000001`**, slice **SST 1**). Must match **ocudu** PLMN/slice and **ru_emulator** UE settings. |
| **`99-uninstall-open5gs.sh`** | **`helm uninstall open5gs -n open5gs`**. Leaves namespace, PVC, Route, SCC YAMLs, etc. |
| **`open5gs-2.2.5.tgz`** | Local chart tarball (from **`helm pull`** if absent). |

## Prerequisites

- OpenShift **`oc`**, **Helm**, and storage suitable for **`30-mongo-pvc.yaml`** (e.g. default SC or cluster-specific class).
- Cluster can pull chart and workload images defined in values files.

## Install

```bash
cd kds/bos2/open5gs
./00-install-open5gs.sh
```

Run **before** **`../ocudu/`** so the AMF service exists for the gNB **`gnb-config.yml`** AMF address.

## Verify installation

```bash
oc get pods -n open5gs
oc get route -n open5gs open5gs-webui-http
```

Wait for deployments (same logic as install tail end):

```bash
./50-rollout-wait.sh
```

Confirm MongoDB and subscriber (script waits for MongoDB Ready, then inserts subscriber):

```bash
oc get pods -n open5gs -l app.kubernetes.io/name=mongodb
```

Optional: open the **webui** Route URL in a browser; use **`oc get route open5gs-webui-http -n open5gs -o jsonpath='{.spec.host}'`**.

### Web UI: HTTP vs HTTPS and SSH tunnels

**`40-webgui-route.yaml`** creates a Route **without** **`spec.tls`**, so the app is reached over **HTTP** on the generated **`*.apps.<cluster>`** hostname. If you use **`https://`** against that host, the OpenShift router may show **Application not available** even when pods are healthy. Use **`http://<route-host>`**, or add **`spec.tls`** with **`termination: edge`** on the Route if you want **HTTPS**.

**SSH port forwarding** often fails for the same reason: the router selects the backend using the HTTP **`Host`** header (and **SNI** for TLS). If the tunneled request sends **`localhost`** or an IP as the host, the route may not match. Prefer reaching the route hostname **directly** from a machine that resolves **`*.apps.<cluster>`**, or configure forwarding so the client still sends the **full route hostname** (and use **HTTP** unless you add edge TLS as above).

## Uninstall

```bash
cd kds/bos2/open5gs
./99-uninstall-open5gs.sh
```

Optional removal of remaining objects (order may require deleting workload first):

```bash
oc delete -f 40-webgui-route.yaml
oc delete -f 37-update-webgui-init.yaml
oc delete -f 36-update-open5gs-scc.yaml
oc delete -f 30-mongo-pvc.yaml
oc delete -f 20-open5gs-ns.yaml
```

Adjust if your cluster recreated resources with different names.
