#!/bin/bash

#deploy open5gs from docker
#helm install open5gs oci://registry-1.docker.io/gradiant/open5gs --version 2.2.5 -f 5gSA-values.yaml -f override-values.yaml -n open5gs

#install open5gs from a local copy. Damn rate limiting
helm install open5gs ~/git/open5gs/open5gs-2.2.5.tgz \
  -f 5gSA-values.yaml \
  -f override-values.yaml \
  -n open5gs
