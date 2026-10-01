#!/bin/bash
set -eu

echo "==> Starting OpenKB $(cat /app/pkg/UPSTREAM_VERSION)"

mkdir -p /app/data/files /app/data/collab \
         /run/openkb/home /run/openkb/php \
         /run/opensearch/config /run/opensearch/logs /tmp/opensearch

# --- One-time secrets (the quickstart .env publishes these; never reuse them) ---
if [[ ! -f /app/data/.secrets.env ]]; then
    echo "==> First run: generating secrets"
    cat > /app/data/.secrets.env <<EOF
DRUPAL_HASH_SALT=$(openssl rand -hex 32)
OKB_COLLAB_CLIENT_ID=$(openssl rand -hex 16)
OKB_COLLAB_CLIENT_SECRET=$(openssl rand -hex 32)
ADMIN_PASSWORD=$(openssl rand -base64 18 | tr -d '/+=')
EOF
fi
chmod 600 /app/data/.secrets.env

# --- Operator settings (OPENAI_API_KEY, heap, external OpenSearch, ...) ---
[[ -f /app/data/env.sh ]] || cp /app/pkg/env.sh.template /app/data/env.sh

# --- The upstream drupal-files volume skeleton ---
if [[ ! -d /app/data/files/config ]]; then
    cp -an /app/files.dist/. /app/data/files/
fi

# The localstorage sqlite backup needs the file to exist; an empty file is a
# valid new SQLite database for Hocuspocus.
[[ -f /app/data/collab/hocuspocus.sqlite ]] || touch /app/data/collab/hocuspocus.sqlite

# shellcheck source=pkg/env.sh
source /app/pkg/env.sh

# --- Bundled OpenSearch: config is regenerated into /run on every start ---
if [[ "${OPENKB_BUNDLED_OPENSEARCH}" == "true" ]]; then
    cp -a /usr/share/opensearch/config/. /run/opensearch/config/
    cat > /run/opensearch/config/opensearch.yml <<EOF
cluster.name: openkb
node.name: openkb
network.host: 127.0.0.1
http.port: 9200
discovery.type: single-node
cluster.default_number_of_replicas: 0
path.data: /var/lib/opensearch
path.logs: /run/opensearch/logs
node.store.allow_mmap: ${OPENSEARCH_ALLOW_MMAP}
EOF
else
    echo "==> Using external OpenSearch at ${OPENSEARCH_URL%%@*}..."
fi

# --- Ownership (backups and restores reset it) ---
chown -R www-data:www-data /app/data/files /run/openkb
chown -R cloudron:cloudron /app/data/collab /var/lib/opensearch /run/opensearch /tmp/opensearch
chown root:root /app/data/.secrets.env /app/data/env.sh

# Up before Apache answers its first request: Apache serves the setup page while
# it exists, and pkg/boot.sh (via openkb-boot) removes it once the site is up.
: > /run/openkb/.openkb-holding
chown www-data:www-data /run/openkb/.openkb-holding

echo "==> Starting supervisor"
exec /usr/bin/supervisord --configuration /etc/supervisor/supervisord.conf --nodaemon -i OpenKB
