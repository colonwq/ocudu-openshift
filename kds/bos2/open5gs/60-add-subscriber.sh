#!/bin/bash

set -e

IMSI="999700000000001"
SUBSCRIBER_DOC='{
  "imsi": "999700000000001",
  "key": "465B5CE8B199B49FAA5F0A2EE238A6BC",
  "opc": "E8ED289DEBA952E4283B54E88E6183CA",
  "ambr": { "uplink": { "value": 1, "unit": 3 }, "downlink": { "value": 1, "unit": 3 } },
  "slice": [
    {
      "sst": 1,
      "default_indicator": true,
      "session": [
        {
          "nssai": { "sst": 1 },
          "session_type": 3,
          "qos": {
            "index": 9,
            "arp": {
              "priority_level": 8,
              "pre_emption_capability": 1,
              "pre_emption_vulnerability": 1
            }
          }
        }
      ]
    }
  ],
  "schema_version": 1
}'

echo "Adding subscriber (IMSI $IMSI) to open5gs MongoDB..."

echo "Waiting for MongoDB pod to be Ready in namespace open5gs..."
if ! oc wait --for=condition=Ready pod -l app.kubernetes.io/name=mongodb -n open5gs --timeout=120s 2>/dev/null; then
  echo "Error: No MongoDB pod became Ready in time, or label app.kubernetes.io/name=mongodb not found."
  exit 1
fi

POD=$(oc get pods -n open5gs -l app.kubernetes.io/name=mongodb -o jsonpath='{.items[0].metadata.name}')
if [[ -z "$POD" ]]; then
  echo "Error: Could not get MongoDB pod name."
  exit 1
fi
echo "Using MongoDB pod: $POD"

# replaceOne with upsert: idempotent (insert or replace)
EVAL="db.subscribers.replaceOne({ imsi: \"$IMSI\" }, $SUBSCRIBER_DOC, { upsert: true })"
if ! oc exec -n open5gs "$POD" -- mongosh open5gs --quiet --eval "$EVAL"; then
  echo "Error: Failed to add subscriber in MongoDB."
  exit 1
fi

echo "Subscriber (IMSI $IMSI) added or updated successfully."
