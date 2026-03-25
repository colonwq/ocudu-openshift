#!/bin/bash

echo "Updating scc"
oc apply -f 09-ruemulator-scc.yaml

echo "Deploying the ru emulator helm chart"
./10-deploy-ruemulator.sh

echo "Waiting for the pod to start"
./50-wait-for-ruemulator.sh
