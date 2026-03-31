#!/bin/bash
# Apply SNO base configuration: MachineConfig, operators (NMState, SR-IOV, LVM),
# PerformanceProfile / hugepages, NMState CR, SR-IOV policies, LVMCluster.
# Run from any directory: paths are resolved relative to this script.
#
# Manifests applied (in order):
#   00-machine-config.yaml
#   10-nmstate-subscription.yaml
#   30-sriov-subscription.yaml
#   31-sriov-operator-config.yaml
#   50-performance.yaml              (PerformanceProfile + Tuned; not 55-performance-profile.yaml — duplicate)
#   51-master-gnb-hugepages-kargs.yaml
#   60-lvm-subscription.yaml
#   70-nmstate
#   80-sriov-config.yaml
#   90-lvmcluster.yaml
#
# Helper scripts: 01-mcp-wait.sh, 92-merge-pull-secret-wait-mcp.sh, 81-wait-after-sriov-apply.sh,
#   95-wait-for-lvmcluster.sh
# Diagnostics (not applied): 82-sriov-diagnose.sh
# Assisted install only (not applied here): agent-config.yaml, assisted-install.txt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Function: wait_for_csv
# Arguments: $1 = Namespace, $2 = Operator Name (e.g., sriov-network-operator)
wait_for_csv() {
    local namespace=$1
    local operator_name=$2
    local selector="operators.coreos.com/${operator_name}.${namespace}"

    echo "Waiting for Operator: $operator_name in Namespace: $namespace..."

    local retry_count=0
    until [[ -n $(oc get csv -n "$namespace" -l "$selector" -o name 2>/dev/null) ]]; do
        if [ $retry_count -gt 20 ]; then
            echo "Error: CSV for $operator_name never appeared after 100 seconds."
            exit 1
        fi
        echo "   --> CSV not found yet, retrying... ($((retry_count*5))s)"
        sleep 5
        retry_count=$((retry_count + 1))
    done

    local csv_name
    csv_name=$(oc get csv -n "$namespace" -l "$selector" -o name)

    oc wait "$csv_name" -n "$namespace" \
        --for=jsonpath='{.status.phase}'=Succeeded \
        --timeout=300s

    echo "✅ Operator $operator_name is ready!"
}

require_files() {
    local f
    for f in \
        00-machine-config.yaml \
        10-nmstate-subscription.yaml \
        30-sriov-subscription.yaml \
        31-sriov-operator-config.yaml \
        50-performance.yaml \
        51-master-gnb-hugepages-kargs.yaml \
        60-lvm-subscription.yaml \
        70-nmstate \
        80-sriov-config.yaml \
        90-lvmcluster.yaml \
        01-mcp-wait.sh \
        92-merge-pull-secret-wait-mcp.sh \
        81-wait-after-sriov-apply.sh \
        95-wait-for-lvmcluster.sh
    do
        if [[ ! -e "$f" ]]; then
            echo "ERROR: required file missing: $SCRIPT_DIR/$f"
            exit 1
        fi
    done
}

require_files

# --- MachineConfig (SCTP, sysctl, ens1f0 MTU, etc.) ---
echo "Apply base OS machine config"
oc apply -f 00-machine-config.yaml

echo "Waiting for things to begin"
sleep 30

bash "$SCRIPT_DIR/01-mcp-wait.sh"

echo "Verifying CatalogSources are functional..."
until oc get packagemanifests -n openshift-marketplace kubernetes-nmstate-operator &> /dev/null; do
    echo "  --> Waiting for CatalogSource gRPC servers to respond..."
    sleep 10
done
echo "✅ CatalogSource is responsive. Proceeding with Subscription."

# --- Merge pull-secret with Podman (docker.io); waits for master MCP ---
echo "Merging cluster pull-secret with Podman auth (see 92-merge-pull-secret-wait-mcp.sh)"
bash "$SCRIPT_DIR/92-merge-pull-secret-wait-mcp.sh"

# --- NMState operator ---
echo "Installing NMState operator"
oc apply -f 10-nmstate-subscription.yaml

wait_for_csv "openshift-nmstate" "kubernetes-nmstate-operator"

# --- SR-IOV operator ---
echo "Installing SR-IOV operator"
oc apply -f 30-sriov-subscription.yaml

wait_for_csv "openshift-sriov-network-operator" "sriov-network-operator"

echo "Applying default SriovOperatorConfig (required for policy / SriovNetworkNodeState reconciliation)"
oc apply -f 31-sriov-operator-config.yaml

# --- Performance tuning ---
echo "Installing Performance tuning settings"
oc apply -f 50-performance.yaml
echo "Applying 1G hugepage kernel args (DPDK/gNB); see 51-master-gnb-hugepages-kargs.yaml"
oc apply -f 51-master-gnb-hugepages-kargs.yaml

echo "Waiting for things to begin"
sleep 30

bash "$SCRIPT_DIR/01-mcp-wait.sh"

# --- LVMS operator ---
echo "Installing LVM Storage operator"
oc apply -f 60-lvm-subscription.yaml

wait_for_csv "openshift-storage" "lvms-operator"

# --- NMState ---
echo "Applying NMState config"
oc apply -f 70-nmstate

# --- SR-IOV policies / NAD ---
echo "Apply SR-IOV config"
oc apply -f 80-sriov-config.yaml
echo "Waiting for possible SR-IOV drain/reboot to finish (see 81-wait-after-sriov-apply.sh)"
bash "$SCRIPT_DIR/81-wait-after-sriov-apply.sh"

# --- LVM storage ---
echo "Creating LVM cluster"
oc apply -f 90-lvmcluster.yaml

bash "$SCRIPT_DIR/95-wait-for-lvmcluster.sh"

echo "*** Base Configuration Complete ***"
