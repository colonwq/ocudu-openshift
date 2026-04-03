#!/bin/bash
# Sanity-check that base-config resources from 00-install-base.sh are present and healthy.
# Does not replace openshift-must-gather or full operator diagnostics; exit 1 if any check fails.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

FAILURES=0

# Colors when a terminal is attached and NO_COLOR is unset (https://no-color.org/)
if [[ -z "${NO_COLOR:-}" ]] && { [[ -t 1 ]] || [[ -t 2 ]]; }; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  NC='\033[0m'
else
  GREEN=''
  RED=''
  NC=''
fi

pass() { printf '  %b✓%b %s\n' "$GREEN" "$NC" "$*"; }
fail() { printf '  %b✗%b %s\n' "$RED" "$NC" "$*" >&2; FAILURES=$((FAILURES + 1)); }

oc_get() {
  oc get "$@" &>/dev/null
}

csv_phase() {
  local ns=$1
  local op_pkg=$2
  local sel="operators.coreos.com/${op_pkg}.${ns}"
  oc get csv -n "$ns" -l "$sel" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true
}

echo "=== Base-config verification (${SCRIPT_DIR}) ==="
echo

echo "MachineConfigs (SCTP/sysctl + hugepages)"
for mc in 00-master-custom-sctp-gnb-params 51-master-gnb-hugepages-kargs; do
  if oc_get machineconfig "$mc"; then
    pass "MachineConfig $mc"
  else
    fail "MachineConfig $mc not found"
  fi
done

echo
echo "Machine Config Pool (master)"
MACHINES=$(oc get mcp master -o jsonpath='{.status.machineCount}' 2>/dev/null || echo "")
READY=$(oc get mcp master -o jsonpath='{.status.readyMachineCount}' 2>/dev/null || echo "")
if [[ -n "$MACHINES" && "$READY" == "$MACHINES" && "$MACHINES" != "0" ]]; then
  pass "mcp/master readyMachineCount=$READY machineCount=$MACHINES"
else
  fail "mcp/master not fully ready (ready=$READY machineCount=$MACHINES)"
fi

echo
echo "PerformanceProfile + Tuned"
if oc_get performanceprofile gnb-performance-profile; then
  pass "PerformanceProfile gnb-performance-profile"
else
  fail "PerformanceProfile gnb-performance-profile not found"
fi
if oc_get tuned gnb-performance -n openshift-cluster-node-tuning-operator; then
  pass "Tuned gnb-performance (openshift-cluster-node-tuning-operator)"
else
  fail "Tuned gnb-performance not found"
fi

echo
echo "NMState operator + CR"
phase=$(csv_phase openshift-nmstate kubernetes-nmstate-operator)
if [[ "$phase" == "Succeeded" ]]; then
  pass "CSV kubernetes-nmstate-operator phase=Succeeded"
else
  fail "CSV kubernetes-nmstate-operator in openshift-nmstate phase='$phase' (want Succeeded)"
fi
if oc_get nmstate nmstate; then
  pass "NMState CR nmstate"
else
  fail "NMState CR nmstate not found (oc get nmstate nmstate)"
fi

echo
echo "SR-IOV operator + config"
phase=$(csv_phase openshift-sriov-network-operator sriov-network-operator)
if [[ "$phase" == "Succeeded" ]]; then
  pass "CSV sriov-network-operator phase=Succeeded"
else
  fail "CSV sriov-network-operator phase='$phase' (want Succeeded)"
fi
if oc_get sriovoperatorconfig default -n openshift-sriov-network-operator; then
  pass "SriovOperatorConfig default"
else
  fail "SriovOperatorConfig default missing"
fi
if oc_get sriovnetworknodepolicy sriov-policy-node-2 -n openshift-sriov-network-operator; then
  pass "SriovNetworkNodePolicy sriov-policy-node-2"
else
  fail "SriovNetworkNodePolicy sriov-policy-node-2 not found"
fi
if oc_get sriovnetwork sriov-ocudu -n openshift-sriov-network-operator; then
  pass "SriovNetwork sriov-ocudu"
else
  fail "SriovNetwork sriov-ocudu not found"
fi

echo
echo "LVMS operator + LVMCluster"
phase=$(csv_phase openshift-storage lvms-operator)
if [[ "$phase" == "Succeeded" ]]; then
  pass "CSV lvms-operator phase=Succeeded"
else
  fail "CSV lvms-operator phase='$phase' (want Succeeded)"
fi
lvm_state=$(oc get lvmcluster lvmcluster -n openshift-storage -o jsonpath='{.status.state}' 2>/dev/null || true)
if [[ "$lvm_state" == "Ready" ]]; then
  pass "LVMCluster openshift-storage/lvmcluster state=Ready"
else
  fail "LVMCluster lvmcluster state='$lvm_state' (want Ready)"
fi
if oc get storageclass 2>/dev/null | grep -qiE 'lvms|vg1'; then
  pass "StorageClass matching lvms|vg1 present"
else
  fail "No StorageClass matching lvms|vg1 (check LVMS / TopoLVM)"
fi

echo
echo "Node allocatable SR-IOV (control-plane node, resource from 80-sriov-config.yaml)"
SRIOV_KEY="openshift.io/sriov_gnb_ens1f0"
NODE=$(oc get nodes -l 'node-role.kubernetes.io/master=' -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$NODE" ]]; then
  NODE=$(oc get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
fi
if [[ -z "$NODE" ]]; then
  fail "Could not determine a node name"
else
  if command -v jq &>/dev/null; then
    val=$(oc get node "$NODE" -o json | jq -r --arg k "$SRIOV_KEY" '.status.allocatable[$k] // empty')
    if [[ -n "$val" ]]; then
      pass "Node $NODE allocatable ${SRIOV_KEY}=${val}"
    else
      fail "Node $NODE missing allocatable $SRIOV_KEY (SR-IOV policy not synced yet? run 82-sriov-diagnose.sh)"
    fi
  else
    if oc describe node "$NODE" 2>/dev/null | grep -qF "$SRIOV_KEY"; then
      pass "Node $NODE describes allocatable $SRIOV_KEY (jq not installed for exact value)"
    else
      fail "Node $NODE: $SRIOV_KEY not found in describe (install jq for stricter check)"
    fi
  fi
fi

echo
if [[ "$FAILURES" -eq 0 ]]; then
  printf '%b=== All checks passed ===%b\n' "$GREEN" "$NC"
  exit 0
fi
printf '%b=== %s check(s) failed ===%b\n' "$RED" "$FAILURES" "$NC" >&2
exit 1
