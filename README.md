# OCUDU OpenShift Cluster Configuration

This repository contains OpenShift cluster configuration manifests and Helm values for deploying a 5G network stack with OCUDU gNB and Open5GS core network.

## Repository Structure

```
.
├── manifests/          # OpenShift cluster infrastructure configuration
└── values/             # Helm chart values for 5G network components
    ├── ocudu-gnb/      # OCUDU 5G gNB configuration
    └── open5gs/        # Open5GS 5G core network configuration
```

## Components

### Infrastructure Manifests (`manifests/`)

OpenShift cluster configuration resources for high-performance 5G workloads:

#### Operators and Namespaces
- **SR-IOV Network Operator**: Provides SR-IOV Virtual Functions for high-performance networking
  - `Namespace_openshift-sriov-network-operator.yaml`
  - `OperatorGroup_sriov-network-operators.yaml`
  - `Subscription_sriov-network-operator-subscription.yaml`
  - `SriovOperatorConfig_default.yaml`

- **NMState Operator**: Declarative network configuration management
  - `Namespace_openshift-nmstate.yaml`
  - `OperatorGroup_openshift-nmstate.yaml`
  - `Subscription_kubernetes-nmstate-operator.yaml`
  - `NMState_nmstate.yaml`

#### Network Configuration
- `SriovNetworkNodePolicy_pci-sriov-net-ens1f0.yaml`: SR-IOV policy for `ens1f0` interface
  - 16 Virtual Functions (VFs) with vfio-pci driver
  - MTU: 9000
  - Resource name: `pci_sriov_net_ens1f0`

- `SriovNetwork_sriov-ocudu.yaml`: SR-IOV network for OCUDU gNB

- `NodeNetworkConfigurationPolicy_ens1f0-policy.yaml`: NMState policy for network interface configuration

#### Performance Tuning
- `PerformanceProfile_openshift-node-performance-profile.yaml`: Node performance optimization
  - CPU isolation: cores 2-27, 30-55
  - CPU reserved: cores 0-1, 28-29
  - Hugepages: 16x 1GB pages
  - Applied to master nodes

- `MachineConfig_load-sctp-module-master.yaml`: Loads SCTP kernel module (required for NGAP/N2 interface)

### Helm Values (`values/`)

#### OCUDU gNB Configuration (`values/ocudu-gnb/values.yaml`)

Configuration for OCUDU 5G gNodeB deployment:

**Key Features:**
- Container: `registry.gitlab.com/ocudu/ocudu/ocudu_nightly_avx512:20260210_0944be1e`
- SR-IOV networking with `openshift.io/pci_sriov_net_ens1f0` resource
- Resources: 12 CPU cores, 16Gi memory, 2Gi hugepages-1Gi
- Network mode: CNI with SR-IOV (not host network)
- O-RAN Fronthaul (OFH) for Radio Unit connectivity

**5G Configuration:**
- PLMN: 00101 (MCC: 001, MNC: 01)
- TAC: 7
- PCI: 1
- Band: 78 (3.5 GHz)
- Bandwidth: 100 MHz
- DL ARFCN: 637212
- TDD configuration: 7DL/2UL slots

**Interfaces:**
- N2 (NGAP): Connects to AMF at `open5gs-amf-ngap.open5gs.svc.cluster.local:38412`
- N3 (GTP-U): User plane to UPF
- OFH: Radio Unit via SR-IOV interface `ens1f0`

#### Open5GS Core Configuration (`values/open5gs/5gSA-values.yaml`)

5G Standalone (SA) core network configuration:

**Enabled Components:**
- AMF (Access and Mobility Management Function)
- SMF (Session Management Function)
- UPF (User Plane Function)
- NRF (Network Repository Function)
- AUSF (Authentication Server Function)
- UDM (Unified Data Management)
- UDR (Unified Data Repository)
- PCF (Policy Control Function)
- BSF (Binding Support Function)
- NSSF (Network Slice Selection Function)
- SCP (Service Communication Proxy)
- WebUI (on NodePort 30002)

**Network Configuration:**
- PLMN: 001/01
- TAC: [7]
- Network Slice: SST=1, SD=0x1
- UE subnet: 10.45.0.1/16 (DNN: srsapn)
- Database: MongoDB (persistent storage required)

## Deployment

### Prerequisites

1. OpenShift cluster (tested on OCP 4.21)
2. SR-IOV capable network interfaces
3. Nodes with AVX512 support (for OCUDU gNB)
4. Storage provisioner for MongoDB persistence

### Installation Steps

1. **Deploy Infrastructure Manifests**
   ```bash
   # Apply all manifests
   oc apply -f manifests/

   # Wait for operators to be ready
   oc wait --for=condition=Available -n openshift-sriov-network-operator deployment/sriov-network-operator
   oc wait --for=condition=Available -n openshift-nmstate deployment/nmstate-operator
   ```

2. **Deploy Open5GS Core**
   ```bash
   # Create project and update namespace pod security
   oc new-project open5gs
   oc label ns open5gs pod-security.kubernetes.io/enforce=privileged --overwrite

   # Grant privileged security context to service accounts
   oc adm policy add-scc-to-user privileged -z default -n open5gs
   oc adm policy add-scc-to-user privileged -z  open5gs-mongodb -n open5gs

   # Create PV and PVC for open5gs-mongodb deployment
   curl https://gitlab.com/ocudu/ocudu_elements/ocudu_helm/-/raw/main/charts/open5gs/open5gs-pv-pvc.yaml?ref_type=heads | oc apply -n open5gs -f -

   # Deploy with custom values
   helm install open5gs oci://registry-1.docker.io/gradiant/open5gs --version 2.2.5 -f values/open5gs/5gSA-values.yaml -n open5gs

   # Patch init container image for the open5gs-webui deployment
   oc patch deployment open5gs-webui -n open5gs --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/initContainers/0/image", "value": "docker.io/bitnamilegacy/mongodb:4.4.1"}]'
   ```

3. **Deploy OCUDU gNB**
   ```bash
   # Create project and update namespace pod security
   oc new-project ocudu
   oc label ns ocudu pod-security.kubernetes.io/enforce=privileged --overwrite

   # Grant privileged security context to service account
   oc adm policy add-scc-to-user privileged -z ocudu-gnb -n ocudu

   # Deploy gNB
   helm install ocudu-gnb oci://registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/ocudu-gnb --version 3.2.0 -f values/ocudu-gnb/values.yaml -n ocudu
   ```

## Network Architecture

```
┌──────────────────────────────────────────────────────────┐
│ OpenShift Cluster                                        │
│                                                          │
│  ┌──────────────┐                      ┌───────────────┐ │
│  │              │                      │  Open5G Core  │ │
│  │              │         N2 (SCTP)    │  ┌─────────┐  │ │
│  │  OCUDU gNB   │◄─────────────────────│──┤   AMF   │  │ │
│  │              │                      │  └─────────┘  │ │
│  │  ┌────────┐  │         N3 (GTP-U)   │  ┌─────────┐  │ │
│  │  │OFH/DPDK│  │◄─────────────────────│──┤   UPF   │  │ │
│  │  │SR-IOV  │  │                      │  └─────────┘  │ │
│  │  └────────┘  │                      │  ┌─────────┐  │ │
│  │      │       │                      │  │   SMF   │  │ │
│  └──────┼───────┘                      │  └─────────┘  │ │
│         │                              │  ┌─────────┐  │ │
│         │                              │  │NRF/UDM/ │  │ │
│    ┌────▼─────┐                        │  │PCF/etc  │  │ │
│    │Radio Unit│                        │  └─────────┘  │ │
│    │  (RU)    │                        │               │ │
│    └──────────┘                        └───────────────┘ │
└──────────────────────────────────────────────────────────┘
```

## Hardware Requirements

### Master Nodes
- CPU: 56+ cores (isolated CPUs: 2-27, 30-55)
- Memory: 32GB+ (16GB for hugepages)
- SR-IOV capable NIC (e.g., Intel X710, Mellanox ConnectX-5)
- AVX512 instruction set support

### Network Interfaces
- Physical interface: `ens1f0`
- 16 SR-IOV Virtual Functions
- MTU: 9000 (jumbo frames)
- Driver: vfio-pci for DPDK

## Configuration Notes

### SR-IOV Resource Naming
The SR-IOV resource name must match across configurations:
- SriovNetworkNodePolicy: `resourceName: pci_sriov_net_ens1f0`
- OCUDU values: `extendedResourceName: openshift.io/pci_sriov_net_ens1f0`
- Pod resources: `openshift.io/pci_sriov_net_ens1f0: 1`

### Network Slice Configuration
Both gNB and core must have matching slice configuration:
- SST: 1
- SD: 0x1 (decimal: 1)

### PLMN Configuration
Ensure consistent PLMN across all components:
- PLMN: "00101" (MCC: 001, MNC: 01)

## Troubleshooting

### Check SR-IOV Status
```bash
oc get sriovnetworknodestates -n openshift-sriov-network-operator
oc get sriovnetwork -n openshift-sriov-network-operator
```

### Check NMState
```bash
oc get nodenetworkstate
oc get nodenetworkconfigurationpolicy
```

### Check Performance Profile
```bash
oc get performanceprofile
oc describe node <node-name> | grep -A 10 Allocatable
```

### View gNB Logs
```bash
oc logs -n gnb deployment/ocudu-gnb -n ocudu -f
```

### View Core Component Logs
```bash
oc logs -n open5gs deployment/open5gs-amf -f
oc logs -n open5gs deployment/open5gs-upf -f
```
