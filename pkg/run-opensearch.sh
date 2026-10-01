#!/bin/bash
set -eu
if [[ "${OPENKB_BUNDLED_OPENSEARCH}" != "true" ]]; then
    echo "opensearch: external cluster configured, bundled node stays off"
    # Supervisor treats exit 0 after startsecs=0 as a clean stop.
    exit 0
fi
cd /tmp/opensearch
exec /usr/share/opensearch/bin/opensearch
