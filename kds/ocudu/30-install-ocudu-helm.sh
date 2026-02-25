#!/bin/bash

helm install ocudu-gnb oci://registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/ocudu-gnb --version 3.2.0 -f 40-values-override.yaml -n ocudu

