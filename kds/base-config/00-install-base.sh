#!/bin/bash

# Function: wait_for_csv
# Arguments: $1 = Namespace, $2 = Operator Name (e.g., sriov-network-operator)
wait_for_csv() {
    local namespace=$1
    local operator_name=$2
    local selector="operators.coreos.com/${operator_name}.${namespace}"
    
    echo "Waiting for Operator: $operator_name in Namespace: $namespace..."

    # 1. Wait for the CSV object to exist (non-empty output)
    local retry_count=0
    # We use -o name to get a clean 'clusterserviceversion.operators.coreos.com/name' string
    until [[ -n $(oc get csv -n "$namespace" -l "$selector" -o name 2>/dev/null) ]]; do
        if [ $retry_count -gt 20 ]; then
            echo "Error: CSV for $operator_name never appeared after 100 seconds."
            exit 1
        fi
        echo "   --> CSV not found yet, retrying... ($((retry_count*5))s)"
        sleep 5
        ((retry_count++))
    done

    # 2. Now wait for the 'Succeeded' phase
    # We get the specific name we found to make the wait command more precise
    local csv_name=$(oc get csv -n "$namespace" -l "$selector" -o name)
    
    oc wait "$csv_name" -n "$namespace" \
        --for=jsonpath='{.status.phase}'=Succeeded \
        --timeout=300s

    echo "✅ Operator $operator_name is ready!"
}

# install base OS machine config
echo "Apply base os machine config"
oc apply -f 00-machine-config.yaml

echo "Waiting for things to begin"
sleep 30

#Wait for the machine config to apply and the host to reboot.
echo "Waiting for SNO to finish rebooting..."
until oc wait mcp master --for='condition=Updated=True' --timeout=10s &> /dev/null; do
  echo "Node is still updating or rebooting... $(date)"
  sleep 15
done
echo "SNO is back online and Updated!"

echo "Verifying CatalogSources are functional..."
until oc get packagemanifests -n openshift-marketplace kubernetes-nmstate-operator &> /dev/null; do
    echo "  --> Waiting for CatalogSource gRPC servers to respond..."
    sleep 10
done
echo "✅ CatalogSource is responsive. Proceeding with Subscription."

#Install the NMState operator
echo "Installing NMState operator"
oc apply -f 10-nmstate-subscription.yaml

#wait for the csv to be ready
wait_for_csv "openshift-nmstate" "kubernetes-nmstate-operator"

#install the SR-IOV operator
echo "Installing SR-IOV operator"
oc apply -f 30-sriov-subscription.yaml

#wait for the csv to be ready
wait_for_csv "openshift-sriov-network-operator" "sriov-network-operator"

##performance tuning
#echo "Installing Performancing tuning settings"
#oc apply -f 50-performance.yaml

#install the lvm storage operator
echo "Installing LVM Storage operator"
oc apply -f 60-lvm-storage.yaml

#wait for the CSV to be ready
wait_for_csv "openshift-storage" "lvms-operator"

#apply the nmstae config
echo "Applying NMState config"
oc apply -f 70-nmstate

#apply the sr-iov config
echo "Apply SR-IOV config"
oc apply -f 80-sriov-config.yaml

#creat the LVM storage cluster/strage class
echo "Creating LVM cluster"
oc apply -f 90-lvmcluster.yaml

#wait for it to be ready
echo "Waiting for LVMCluster to reach Ready state..."
# Loop until the state is exactly "Ready"
until [ "$(oc get lvmcluster lvmcluster -n openshift-storage -o jsonpath='{.status.state}' 2>/dev/null)" == "Ready" ]; do
    CURRENT_STATE=$(oc get lvmcluster lvmcluster -n openshift-storage -o jsonpath='{.status.state}' 2>/dev/null || echo "Unknown")
    echo "  --> LVMCluster is currently: $CURRENT_STATE. Waiting..."
    sleep 5
done
echo "✅ LVMCluster is now Ready!"

echo "*** Base Configuration Complete ***"
