#!/bin/bash

echo "Create the open5gs namespace" 
oc apply -f 20-open5gs-ns.yaml

echo "Create the mongodb PVC"
oc apply -f 30-mongo-pvc.yaml

echo "Deploy the open5gs helm chart"
./35-deploy-open5gs.sh

echo "Update the SCC to allow the replica sets to deploy"
oc apply -f 36-update-open5gs-scc.yaml

echo "Update the webgui deployment to allow the init to start"
oc apply -f 37-update-webgui-init.yaml

echo "Expose the webgui route"
oc apply -f 40-webgui-route.yaml
