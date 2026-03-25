#!/bin/bash

for deploy in $(oc get deployments -n open5gs -o name); do oc rollout status $deploy -n open5gs --timeout=300s; done
