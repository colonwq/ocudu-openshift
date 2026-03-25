#!/bin/bash

echo "Uninstalling ru-emulator helm release..."
helm uninstall ru-emulator -n ocudu

echo "Done. Namespace ocudu and other resources (SCC, etc.) are left in place."
echo "To remove SCC only, run: oc delete -f 09-ruemulator-scc.yaml"
