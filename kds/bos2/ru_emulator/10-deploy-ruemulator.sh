#!/bin/bash

helm install ru-emulator oci://registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/ru-emulator --version 2.0.0-dev -f ./values.yaml -n ocudu

