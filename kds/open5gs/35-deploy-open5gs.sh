#!/bin/bash

#deploy open5gs
#helm install open5gs oci://registry-1.docker.io/gradiant/open5gs --version 2.2.5 -f 5gSA-values.yaml -f override-values.yaml -n open5gs
helm install open5gs oci://registry-1.docker.io/gradiant/open5gs --version 2.2.5 -f 5gSA-values.yaml -n open5gs
