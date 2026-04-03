# ocudu-gnb deployment (OpenShift)

This directory installs the **ocudu-gnb** Helm chart into the **`ocudu`** namespace: the 5G gNB workload (DPDK/SR-IOV-oriented) used with **open5gs** and optionally **ru_emulator** in this repo.

Chart source: GitLab OCI **`registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/ocudu-gnb`**. Image tags and platform mapping live in **`30-install-ocudu-helm.sh`**.

## Files

| File | Role |
|------|------|
| **`00-install-ocudu.sh`** | Wrapper: namespace → SCC → Helm → wait for Ready gNB pod. Optional **`-p`** selects image platform (**`f`** fedora default, **`c`** centos, **`r`** redhat, **`u`** ubuntu). |
| **`10-ocudu-ns.yaml`** | **`Namespace`** **`ocudu`** with privileged pod security enforcement. |
| **`20-ocudu-scc.yaml`** | **`RoleBinding`**: grants **`system:openshift:scc:privileged`** to ServiceAccount **`ocudu-gnb`** in **`ocudu`** (required for the chart’s workload). |
| **`30-install-ocudu-helm.sh`** | **`helm install ocudu-gnb`**: pulls **`ocudu-gnb-3.2.0.tgz`** from OCI if missing, installs with **`40-values-override.yaml`** and **`--set image.tag=…`** from platform. |
| **`40-values-override.yaml`** | Helm values: image repo/tag overrides, **SR-IOV / Multus**, **`runtimeClassName`**, **`gnb-config.yml`** (AMF address, PLMN, **`remote_control`** port **8001**, metrics, etc.). Must stay aligned with **open5gs** subscriber slice (**`../open5gs/60-add-subscriber.sh`**) and **ru_emulator** UE config if used. |
| **`50-wait-for-ocudu.sh`** | Waits up to **300s** for a **Ready** pod with **`app.kubernetes.io/name=ocudu-gnb`** in **`ocudu`**; prints diagnostics on failure. |
| **`99-uninstall-ocudu.sh`** | **`helm uninstall ocudu-gnb -n ocudu`**. Leaves namespace, SCC binding, and other cluster objects unless you delete them manually. |
| **`ocudu-gnb-3.2.0.tgz`** | Local chart archive (created by **`helm pull`** if absent). Not stored in git if ignored. |

## Prerequisites

- OpenShift cluster with **Helm** / **`oc`** configured; SR-IOV and **PerformanceProfile** if you use the values in **`40-values-override.yaml`** (see **`../base-config/`** in this repo).
- **open5gs** AMF reachable at the host configured under **`cu_cp.amf.addr`** in **`40-values-override.yaml`** (typically **`open5gs-amf-ngap.open5gs.svc.cluster.local`** after **`../open5gs/`** install).
- Cluster pull access to the gNB container image in **`40-values-override.yaml`**.

## Install

```bash
cd kds/bos2/ocudu
./00-install-ocudu.sh              # default: fedora platform image
./00-install-ocudu.sh -p r         # example: redhat platform tag
```

Typical stack order in **`../install.sh`**: **base-config** → **open5gs** → **ocudu** → **ru_emulator**.

## Verify installation

```bash
oc get pods -n ocudu -l app.kubernetes.io/name=ocudu-gnb
oc wait --for=condition=Ready pod -l app.kubernetes.io/name=ocudu-gnb -n ocudu --timeout=60s
```

Confirm AMF connectivity and gNB logs as needed:

```bash
oc logs -n ocudu -l app.kubernetes.io/name=ocudu-gnb --tail=80
```

Optional: after **[`../telegraf/`](../telegraf/)** is installed, confirm **`remote_control`** / metrics path per that README.

## Uninstall

```bash
cd kds/bos2/ocudu
./99-uninstall-ocudu.sh
```

Optional full cleanup of namespace + SCC manifest (only if nothing else should remain in **`ocudu`**):

```bash
oc delete -f 20-ocudu-scc.yaml
oc delete -f 10-ocudu-ns.yaml
```

**Warning:** Deleting **`ocudu`** removes **ru_emulator** and any other workloads in that namespace.
