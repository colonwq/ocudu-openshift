#!/bin/bash
# Run after: oc apply -f 80-sriov-config.yaml
#
# SriovNetworkNodePolicy (VF creation, vfio-pci, etc.) often triggers a node drain and reboot.
# Reboot is not guaranteed for every change, but when it happens the node may leave Ready briefly
# or stay NotReady for several minutes.
#
# This script waits until all nodes are Ready for three consecutive checks (20s apart) so we
# do not exit early if a reboot starts shortly after apply.
#
# Env: MAX_WAIT_SEC (default 2700), STABLE_CHECKS (default 3), POLL_SEC (default 20)

set -euo pipefail

MAX_WAIT_SEC="${MAX_WAIT_SEC:-2700}"
STABLE_CHECKS="${STABLE_CHECKS:-3}"
POLL_SEC="${POLL_SEC:-20}"

started="$(date +%s)"
stable=0

echo "Waiting for all nodes to be Ready (SR-IOV may have triggered a reboot; max ${MAX_WAIT_SEC}s)..."
echo "  Require ${STABLE_CHECKS} consecutive Ready checks, ${POLL_SEC}s apart."

while true; do
  now="$(date +%s)"
  if (( now - started > MAX_WAIT_SEC )); then
    echo "Timeout after ${MAX_WAIT_SEC}s. Check: oc get nodes; oc get sriovnetworknodestate -n openshift-sriov-network-operator"
    exit 1
  fi

  if oc wait nodes --all --for=condition=Ready --timeout=15s 2>/dev/null; then
    stable=$((stable + 1))
    echo "  --> All nodes Ready (${stable}/${STABLE_CHECKS} stable checks)"
    if (( stable >= STABLE_CHECKS )); then
      echo "✅ All nodes stayed Ready; SR-IOV reconcile / reboot window looks complete."
      if oc get sriovnetworknodestate -n openshift-sriov-network-operator &>/dev/null; then
        oc get sriovnetworknodestate -n openshift-sriov-network-operator -o wide 2>/dev/null || true
      fi
      exit 0
    fi
  else
    if (( stable > 0 )); then
      echo "  --> Node(s) not Ready; reset stable counter (drain/reboot likely)."
    else
      echo "  --> Node(s) not Ready... $(date -Is)"
    fi
    stable=0
  fi

  sleep "$POLL_SEC"
done
