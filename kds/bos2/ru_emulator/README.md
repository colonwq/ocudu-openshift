# ru_emulator deployment (OpenShift)

This directory installs the **ru-emulator** Helm chart into the **`ocudu`** namespace (same project as **ocudu-gnb**). It emulates RU/O-RAN style behavior for lab testing against the gNB.

Chart OCI: **`registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/ru-emulator`**, version **`2.0.0-dev`** (local **`ru-emulator-2.0.0-dev.tgz`** pulled if missing).

## Files

| File | Role |
|------|------|
| **`00-install-ru-emulator.sh`** | Applies SCC binding, runs Helm deploy, waits for Ready **ru-emulator** pod. |
| **`09-ruemulator-scc.yaml`** | **`RoleBinding`**: grants **`system:openshift:scc:privileged`** to **`default`** ServiceAccount in **`ocudu`** (required for emulator privileges on OCP). |
| **`10-deploy-ruemulator.sh`** | **`helm install ru-emulator`** with **`values.yaml`** in **`ocudu`**. |
| **`values.yaml`** | Chart values: image, subscriber / UE credentials, networking—must stay consistent with **`../open5gs/60-add-subscriber.sh`** and **`../ocudu/40-values-override.yaml`**. |
| **`50-wait-for-ruemulator.sh`** | Waits up to **300s** for **Ready** pod **`app.kubernetes.io/name=ru-emulator`** in **`ocudu`**; prints diagnostics on failure. |
| **`99-uninstall-ru-emulator.sh`** | **`helm uninstall ru-emulator -n ocudu`**. Does not remove **ocudu-gnb** or the namespace. |
| **`values.yaml.ORIG`**, **`values.yaml.BORK`** | Backup / experiment copies; not used by install scripts. |
| **`ru-emulator-2.0.0-dev.tgz`** | Local chart archive (from **`helm pull`** if absent). |

## Prerequisites

- **`ocudu`** namespace and **ocudu-gnb** typically already installed (**`../ocudu/00-install-ocudu.sh`**).
- **open5gs** subscriber and **ocudu** cell PLMN/slice aligned with **`values.yaml`** UE configuration.
- Cluster pull access to the ru-emulator image referenced in **`values.yaml`**.

## Install

```bash
cd kds/bos2/ru_emulator
./00-install-ru-emulator.sh
```

In **`../install.sh`**, this step runs **after** **open5gs** and **ocudu**.

## Verify installation

```bash
oc get pods -n ocudu -l app.kubernetes.io/name=ru-emulator
oc wait --for=condition=Ready pod -l app.kubernetes.io/name=ru-emulator -n ocudu --timeout=60s
```

Inspect logs if the gNB does not see expected RU activity:

```bash
oc logs -n ocudu -l app.kubernetes.io/name=ru-emulator --tail=100
```

## Uninstall

```bash
cd kds/bos2/ru_emulator
./99-uninstall-ru-emulator.sh
```

Optional: remove only the SCC **`RoleBinding`** manifest if no other workload in **`ocudu`** needs it:

```bash
oc delete -f 09-ruemulator-scc.yaml
```

**Note:** **`99-uninstall-ru-emulator.sh`** does **not** delete **`ocudu`** or **ocudu-gnb**.
