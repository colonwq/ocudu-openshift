#!/bin/bash

NAME="ru_emulator"
NAMESPACE="ocudu"
LABEL="app.kubernetes.io/name=ru-emulator"
TIMEOUT="300s"

echo "Waiting for ${NAME} Pod ($LABEL) in namespace $NAMESPACE..."

# The 'oc wait' command returns 0 on success, and non-zero on timeout/error
if oc wait --for=condition=Ready pod -l "$LABEL" -n "$NAMESPACE" --timeout="$TIMEOUT"; then
    echo "---------------------------------------------------"
    echo "✅ SUCCESS: The ${NAME} Pod is now RUNNING and READY!"
    echo "---------------------------------------------------"
    oc get pods -n "$NAMESPACE" -l "$LABEL"
else
    echo "---------------------------------------------------"
    echo "❌ FAILURE: The ${NAME} Pod failed to reach Ready state within $TIMEOUT."
    echo "---------------------------------------------------"
    
    # Diagnostic: Check if the pod actually exists but is crashing
    POD_STATUS=$(oc get pods -n "$NAMESPACE" -l "$LABEL" -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    
    if [ -z "$POD_STATUS" ]; then
        echo "Reason: No Pod with label $LABEL was ever created."
    else
        echo "Current Pod Status: $POD_STATUS"
        echo "Checking for CrashLoopBackOff or ImagePullErrors..."
        oc get pods -n "$NAMESPACE" -l "$LABEL"
        
        echo -e "\nRecent Events for this Pod:"
        oc get events -n "$NAMESPACE" --field-selector involvedObject.kind=Pod | tail -n 5
    fi
    exit 1
fi
