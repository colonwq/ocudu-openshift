#!/bin/bash
echo "Waiting for LVMCluster to reach Ready state..."
# Loop until the state is exactly "Ready"
until [ "$(oc get lvmcluster lvmcluster -n openshift-storage -o jsonpath='{.status.state}' 2>/dev/null)" == "Ready" ]; do
    CURRENT_STATE=$(oc get lvmcluster lvmcluster -n openshift-storage -o jsonpath='{.status.state}' 2>/dev/null || echo "Unknown")
    echo "  --> LVMCluster is currently: $CURRENT_STATE. Waiting..."
    sleep 5
done
echo "✅ LVMCluster is now Ready!"
