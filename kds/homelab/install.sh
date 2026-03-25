#!/bin/bash

# Exit on any error
set -e
#set -x

echo "Starting Open5GS and OCU DU Deployment..."

export KUBECONFIG=/home/kschinck/Downloads/kubeconfig

echo "Calling the base config install"
./base-config/00-install-base.sh

echo "Calling the open5gs install"
./open5gs/00-install-open5gs.sh

echo "Calling the ocudu install"
./ocudu/00-install-ocudu.sh

echo "Calling the ruemulator install"
./ru_emulator/00-install-ru-emulator.sh
