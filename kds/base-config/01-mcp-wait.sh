#!/bin/bash

echo "Waiting for SNO to finish rebooting..."
until oc wait mcp master --for='condition=Updated=True' --timeout=10s &> /dev/null; do
  echo "Node is still updating or rebooting... $(date)"
  sleep 15
done
echo "SNO is back online and Updated!"
