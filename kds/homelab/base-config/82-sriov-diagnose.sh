#!/bin/bash
# Gather SR-IOV operator state when node allocatable has no openshift.io/sriov_* extended resource.
# Usage: ./82-sriov-diagnose.sh [node-name]

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

echo "=== SriovNetworkNodeState ==="
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

echo "=== Pods ==="
oc get pods -n "$NS" -o wide 2>/dev/null || true
echo ""

echo "=== Node SR-IOV extended resources (allocatable) ==="
if [[ -n "$NODE" ]]; then
  oc describe node "$NODE" 2>/dev/null | grep -E 'Allocatable:|Capacity:|openshift.io/sriov|pci_sriov' || true
else
  for n in $(oc get nodes -o jsonpath='{.items[*].metadata.name}'); do
    echo "--- $n ---"
    oc describe node "$n" 2>/dev/null | grep -E 'openshift.io/sriov|pci_sriov' || echo "(no openshift.io/sriov_* / pci_sriov lines)"
  done
fi
echo ""

echo "=== Operator logs (last 40 lines) ==="
oc logs -n "$NS" deploy/sriov-network-operator --tail=40 2>/dev/null || true
echo ""

echo "=== sriov-device-plugin (allocates openshift.io/<resourceName>, e.g. openshift.io/sriov_gnb_enp2s0 on OCP 4.21+) ==="
if oc get ds sriov-device-plugin -n "$NS" &>/dev/null; then
  oc logs -n "$NS" daemonset/sriov-device-plugin --tail=80 2>/dev/null || true
fi
echo ""

echo "=== Config-daemon logs ==="
if [[ -n "$NODE" ]]; then
  pod=$(oc get pods -n "$NS" -l app=sriov-network-config-daemon --field-selector "spec.nodeName=$NODE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  [[ -n "$pod" ]] && oc logs -n "$NS" "$pod" --tail=30 2>/dev/null || echo "No daemon pod on $NODE"
else
  for p in $(oc get pods -n "$NS" -l app=sriov-network-config-daemon -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    echo "--- $p ---"
    oc logs -n "$NS" "$p" --tail=25 2>/dev/null || true
  done
fi
