#!/bin/bash

# Exit on any error
set -e
#set -x

echo "Starting Open5GS and OCU DU Deployment..."

export KUBECONFIG=/home/kschinck/Downloads/kubeconfig

# --- Section 1: Open5GS Infrastructure and Core ---
echo "--- Processing directory: open5gs ---"
cd open5gs

# 1. Apply MachineConfig (Triggers Reboot)
echo "Applying MachineConfig..."
oc apply -f 00-machine-config.yaml

#need time for the MCP to start applying
sleep 30

# 2. Run the MCP Wait script
# We use 'bash' to run it directly in case it isn't marked executable
echo "Waiting for node reboot and MCP update..."
bash 01-mcp-wait.sh

# 3. Apply the rest of the Open5GS manifests in order
# Skipping 00 and 01 as they were handled above
for file in 05-*.yaml 10-*.yaml 20-*.yaml 30-*.yaml; do
    echo "Applying $file..."
    oc apply -f "$file"
done

# 4. Execute the Open5GS deployment script (Helm/OC)
echo "Executing 35-deploy-open5gs.sh..."
bash 35-deploy-open5gs.sh

# 5. Apply post-deployment patches and routes
for file in 36-*.yaml 37-*.yaml 40-*.yaml; do
    echo "Applying $file..."
    oc apply -f "$file"
done

cd ..

#lets let open5gs setttle before deploying ocudu
sleep 30

# --- Section 2: OCU DU Components ---
echo "--- Processing directory: ocudu ---"
cd ocudu

# 1. Apply Namespace and SCC
oc apply -f 10-ocudu-ns.yaml
oc apply -f 20-ocudu-scc.yaml

# 2. Run the Helm installation
# We pass the override file path as an argument if your script supports it
echo "Installing OCU DU Helm Chart..."
bash 30-install-ocudu-helm.sh

cd ..

echo "Deployment Sequence Completed Successfully!"
