# Base configuration (OpenShift SNO / lab)

This directory applies **cluster-level** settings used by **`../ocudu/`**, **`../open5gs/`**, and **`../ru_emulator/`**: MachineConfigs (SCTP, sysctl, hugepages), **NMState**, **SR-IOV** (VF policy + `SriovNetwork` into **`ocudu`**), **PerformanceProfile** + **Tuned**, and **LVM Storage (LVMS)** with an **LVMCluster** (e.g. **`lvms-vg1`** `StorageClass` for PVCs).

Run **`00-install-base.sh`** once per cluster (or after intentional changes). It is **destructive to node state** in the sense that MachineConfigs and SR-IOV policies can trigger drains/reboots—see script comments and **`81-wait-after-sriov-apply.sh`**.

| File | Role |
|------|------|
| **`00-install-base.sh`** | Applies manifests and runs wait helpers in order (see table below). |
| **`99-verify.sh`** | Read-only checks that key resources exist and operators/LVM/SR-IOV look healthy (see **Verify**). |

## What gets applied (order)

Documented in **`00-install-base.sh`**:

| Step | Artifact | Purpose |
|------|----------|---------|
| 1 | **`00-machine-config.yaml`** | Master **MachineConfig**: SCTP load, sysctl tuning, related host files. |
| 2 | **`01-mcp-wait.sh`** | Waits for **Machine Config Pool** (e.g. master) to finish after MC changes. |
| 3 | **`92-merge-pull-secret-wait-mcp.sh`** | Merges pull-secret (e.g. registry creds); waits for MCP again. |
| 4 | **`10-nmstate-subscription.yaml`** | **NMState** operator install (namespace, OperatorGroup, Subscription). |
| 5 | **`30-sriov-subscription.yaml`** | **SR-IOV Network Operator** install. |
| 6 | **`31-sriov-operator-config.yaml`** | **`SriovOperatorConfig` `default`** (required before policies reconcile). |
| 7 | **`50-performance.yaml`** | **`PerformanceProfile` `gnb-performance-profile`** + **`Tuned` `gnb-performance`**. |
| 8 | **`51-master-gnb-hugepages-kargs.yaml`** | Master **MachineConfig**: 1G hugepages kernel args for DPDK/gNB. |
| 9 | **`60-lvm-subscription.yaml`** | **LVMS** operator in **`openshift-storage`**. |
| 10 | **`70-nmstate`** | **`NMState`** CR (enables NMState controller). |
| 11 | **`80-sriov-config.yaml`** | **`SriovNetworkNodePolicy`**, **`SriovNetwork`** (`sriov-ocudu` → **`ocudu`** namespace). |
| 12 | **`81-wait-after-sriov-apply.sh`** | Waits out SR-IOV–related drain/reboot churn. |
| 13 | **`90-lvmcluster.yaml`** | **`LVMCluster` `lvmcluster`** (e.g. **`vg1`** on **`/dev/nvme0n1`**—adjust for your hardware). |
| 14 | **`95-wait-for-lvmcluster.sh`** | Waits until **`LVMCluster`** **`.status.state`** is **Ready**. |

## Other files (reference / optional)

| File | Role |
|------|------|
| **`55-performance-profile.yaml`** | Duplicate **PerformanceProfile** content; **not** applied by **`00-install-base.sh`** (use **`50-performance.yaml`**). |
| **`82-sriov-diagnose.sh`** | Manual SR-IOV troubleshooting (not invoked by install). |
| **`91-assisted-installer-wipe-nvme-machineconfig.yaml`** | Assisted install / disk wipe scenario; **not** part of **`00-install-base.sh`**. |
| **`agent-config.yaml`**, **`assisted-install.txt`** | Assisted installer artifacts; **not** applied here. |

## Prerequisites

- **`oc`** and **`helm`** (for downstream dirs); cluster-admin (or equivalent) to install operators and MachineConfigs.
- Hardware paths in **`80-sriov-config.yaml`** (`rootDevices`) and **`90-lvmcluster.yaml`** (`deviceSelector.paths`) must match the node (see comments in those files).
- Catalog sources (**`redhat-operators`**) reachable for Subscriptions.

## Install

```bash
cd kds/bos2/base-config
./00-install-base.sh
```

Expect **long** runtime (operator installs, MCP updates, possible reboots). See **`81-wait-after-sriov-apply.sh`** and **`01-mcp-wait.sh`**.

## Verify

After install (or any time you want a sanity check):

```bash
cd kds/bos2/base-config
./99-verify.sh
```

The script checks (non-exhaustive but practical): key **MachineConfigs**, **PerformanceProfile** / **Tuned**, operator **CSV** phases, **SriovOperatorConfig**, **SriovNetwork** / **NodePolicy**, **NMState** CR, **LVMCluster** **Ready**, a **StorageClass** hint for LVMS/vg1, and **SR-IOV extended resource** allocatable on a control-plane node (name aligned with **`80-sriov-config.yaml`**).

For deeper SR-IOV issues, run **`./82-sriov-diagnose.sh`** (see script usage).

## Uninstall

There is **no** single **`99-uninstall-base.sh`**: these objects are tightly coupled to the cluster. Removing them typically requires deliberate **`oc delete`** of each CR/operator subscription and may **not** be reversible without reinstalling the node or cluster.

If you must tear down:

- Uninstall workload charts first (**`../ocudu`**, **`../open5gs`**, **`../ru_emulator`**, **`../telegraf`**).
- Delete **SR-IOV** / **LVM** / **NMState** resources in reverse dependency order (consult OpenShift docs for your version).
- **MachineConfigs** should be removed only with a plan for MCP rollout and reboots.

## Related directories

- **`../ocudu/40-values-override.yaml`**: **`runtimeClassName`**, **Multus** NAD **`sriov-ocudu`**, **`openshift.io/sriov_gnb_ens1f0`** requests—must match **`80-sriov-config.yaml`** **`resourceName`** and OCP allocatable name.
- **`../open5gs/`**, **`../ru_emulator/`**: often use **`StorageClass`** from this LVM stack (e.g. **`lvms-vg1`**).
