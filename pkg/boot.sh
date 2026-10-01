#!/bin/bash
# Brings the Drupal site up, as www-data, once per container start. The
# Cloudron counterpart of upstream's openkb-entrypoint background boot:
#
#  1. wait for the bundled OpenSearch (site-install.sh only waits 60 s, a cold
#     JVM in a memory-limited container can take longer),
#  2. after an image update: run openkb-update once (updatedb, deploy hooks,
#     config import, cache rebuild). Upstream never runs updates unattended;
#     on Cloudron every update is preceded by a backup, so this is safe here,
#  3. openkb-boot: installs on an empty database, holds the site if updates are
#     still pending, and removes the setup-page marker when done,
#  4. bundled OpenSearch came up empty for an installed site (restore, or the
#     persistentDir was lost): rebuild the search indexes.
set -u
source /app/pkg/env.sh
cd /app || exit 1

INSTALLED=/app/data/files/.openkb-installed
BUILD_MARKER=/app/data/files/.cloudron-build-id

if [[ "${OPENKB_BUNDLED_OPENSEARCH}" == "true" ]]; then
    echo "boot: waiting for OpenSearch..."
    for i in $(seq 1 300); do
        curl -sf "${OPENSEARCH_URL}/_cluster/health" >/dev/null 2>&1 && { echo "boot: OpenSearch up after ${i}s"; break; }
        [[ $i -eq 300 ]] && echo "boot: OpenSearch did not answer in 300 s, continuing anyway" >&2
        sleep 1
    done
fi

if [[ -f "$INSTALLED" && "$(cat "$BUILD_MARKER" 2>/dev/null)" != "$OPENKB_BUILD_ID" ]]; then
    echo "boot: new image (${OPENKB_BUILD_ID}), running openkb-update"
    if openkb-update; then
        echo "$OPENKB_BUILD_ID" > "$BUILD_MARKER"
    else
        echo "boot: openkb-update FAILED; the site stays held until updates are run (drush updatedb)." >&2
    fi
fi

/usr/local/bin/openkb-boot || exit 1

if [[ -f "$INSTALLED" ]]; then
    echo "$OPENKB_BUILD_ID" > "$BUILD_MARKER"

    if [[ "${OPENKB_BUNDLED_OPENSEARCH}" == "true" ]]; then
        user_indices=$(curl -sf "${OPENSEARCH_URL}/_cat/indices?h=index" | grep -vc '^\.' || true)
        if [[ "${user_indices:-0}" -eq 0 ]]; then
            echo "boot: OpenSearch holds no indexes for an installed site, rebuilding them"
            /app/pkg/reindex.sh || echo "boot: reindex failed, run /app/pkg/reindex.sh by hand" >&2
        fi
    fi
fi
