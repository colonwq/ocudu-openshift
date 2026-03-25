#!/bin/bash

echo "Uninstalling ocudu helm release..."
helm uninstall ocudu-gnb -n ocudu

echo "Done. Namespace ocudu and other resources (SCC, etc.) are left in place."
echo "To remove namespace and applied manifests, run: oc delete -f 20-ocudu-scc.yaml; oc delete -f 10-ocudu-ns.yaml"
