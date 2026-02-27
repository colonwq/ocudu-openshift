#!/bin/bash

echo "Creating the ocudu namespace"
oc apply -f 10-ocudu-ns.yaml

echo "Applying SCC" 
oc apply -f 20-ocudu-scc.yaml

echo "Installing ocudu helm chart"
./30-install-ocudu-helm.sh

echo "Waiting for ocudu to be running"
./50-wait-for-ocudu.sh
