#!/bin/bash

echo "Uninstalling open5gs helm release..."
helm uninstall open5gs -n open5gs

echo "Done. Namespace open5gs and other resources (SCC, PVC, route, etc.) are left in place."
echo "To remove namespace and applied manifests, run: oc delete -f 36-update-open5gs-scc.yaml; oc delete -f 40-webgui-route.yaml; oc delete -f 37-update-webgui-init.yaml; oc delete -f 30-mongo-pvc.yaml; oc delete -f 20-open5gs-ns.yaml"
