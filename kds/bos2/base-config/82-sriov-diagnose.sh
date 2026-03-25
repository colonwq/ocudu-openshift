#!/bin/bash
# Gather SR-IOV operator state when `oc describe node ... | grep pci_sriov` is empty.
# Run from anywhere with a working `oc` and kubeconfig.
# Usage: ./82-sriov-diagnose.sh [node-name]
# Example: ./82-sriov-diagnose.sh node-hpe1

NS="openshift-sriov-network-operator"
NODE="${1:-}"

echo "========== SR-IOV diagnostics ($NS) =========="
echo ""

echo "=== Namespace / Subscription / CSV ==="
oc get ns "$NS" 2>/dev/null || { echo "ERROR: namespace $NS not found"; exit 1; }
oc get subscription,csv -n "$NS" 2>/dev/null || true
echo ""

echo "=== SriovOperatorConfig (required) ==="
oc get sriovoperatorconfig default -n "$NS" -o yaml 2>/dev/null || echo "MISSING: oc apply -f 31-sriov-operator-config.yaml"
echo ""

echo "=== SriovNetworkNodePolicy / SriovNetwork ==="
oc get sriovnetworknodepolicy -n "$NS" -o wide 2>/dev/null || true
oc get sriovnetwork -n "$NS" 2>/dev/null || true
echo ""

echo "=== SriovNetworkNodeState (if empty, policies are not applied on any node) ==="
if oc get sriovnetworknodestate -n "$NS" &>/dev/null; then
  oc get sriovnetworknodestate -n "$NS" -o wide
  for s in $(oc get sriovnetworknodestate -n "$NS" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    echo ""
    echo "--- oc describe sriovnetworknodestate/$s ---"
    oc describe sriovnetworknodestate "$s" -n "$NS" 2>/dev/null | tail -100
  done
else
  echo "No SriovNetworkNodeState resources."
fi
echo ""

echo "=== Pods (operator, config-daemon, device-plugin, webhook) ==="
oc get pods -n "$NS" -o wide 2>/dev/null || true
echo ""

echo "=== Node pci_sriov allocatable ==="
if [[ -n "$NODE" ]]; then
  oc describe node "$NODE" 2>/dev/null | grep -E 'Allocatable:|pci_sriov|Capacity:' || true
else
  for n in $(oc get nodes -o jsonpath='{.items[*].metadata.name}'); do
    echo "--- $n ---"
    oc describe node "$n" 2>/dev/null | grep -E 'pci_sriov' || echo "(no pci_sriov lines)"
  done
fi
echo ""

echo "=== Operator logs (last 40 lines) ==="
oc logs -n "$NS" deploy/sriov-network-operator --tail=40 2>/dev/null || echo "(no operator deployment logs)"
echo ""

echo "=== Config-daemon on ${NODE:-all nodes} (last 30 lines each) ==="
if [[ -n "$NODE" ]]; then
  pod=$(oc get pods -n "$NS" -l app=sriov-network-config-daemon --field-selector "spec.nodeName=$NODE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [[ -n "$pod" ]]; then
    oc logs -n "$NS" "$pod" --tail=30 2>/dev/null || true
  else
    echo "No sriov-network-config-daemon pod on $NODE"
  fi
else
  for p in $(oc get pods -n "$NS" -l app=sriov-network-config-daemon -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    echo "--- $p ---"
    oc logs -n "$NS" "$p" --tail=25 2>/dev/null || true
  done
fi
echo ""

echo "========== Next steps =========="
echo "1) If SriovNetworkNodeState is missing: fix CSV/operator pods and ensure 'default' SriovOperatorConfig exists."
echo "2) If describe nodestate shows SyncFailed / PF not found: fix 80-sriov-config.yaml pfNames to match the host."
echo "   On node: oc debug node/<name> -- chroot /host ip -br link"
echo "3) If PF is enslaved to ovs-system, use a dedicated NIC or reconfigure cluster networking (SR-IOV cannot use that PF as-is)."
echo "4) If numVfs exceeds NIC capability, lower numVfs in the policy."
