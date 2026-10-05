#!/bin/bash
# Maps the Cloudron environment onto the variables the OpenKB images read
# (upstream .env.example and docker-compose.yml). Sourced by start.sh, boot.sh,
# cron.sh and the drush wrapper, so it is re-read on every start and every cron
# run: Cloudron may change addon credentials between restarts.
#
# shellcheck disable=SC2034 # exported (set -a) for the processes started by the callers above, not read in this file

# The longest common dot-suffix of two hostnames, with a leading dot
# (kb.example.com + kb-admin.example.com -> .example.com).
okb_common_parent() {
    local -a a b
    local suffix="" i j
    IFS=. read -ra a <<< "$1"
    IFS=. read -ra b <<< "$2"
    i=${#a[@]}; j=${#b[@]}
    while (( i > 0 && j > 0 )) && [[ "${a[i-1]}" == "${b[j-1]}" ]]; do
        suffix=".${a[i-1]}${suffix}"
        i=$((i - 1)); j=$((j - 1))
    done
    echo "$suffix"
}

set -a

# Operator overrides first, so the defaults below only fill what is unset.
[[ -r /app/data/env.sh ]] && source /app/data/env.sh
[[ -r /app/data/.secrets.env ]] && source /app/data/.secrets.env

OPENKB_BUILD_ID=$(cat /app/pkg/BUILD_ID 2>/dev/null || echo unknown)

# --- The two URLs ---
if [[ -z "${ADMIN_DOMAIN:-}" ]]; then
    echo "env.sh: ADMIN_DOMAIN is unset; the Drupal domain must be assigned in the app's location settings." >&2
fi
DRUPAL_FRONTEND_BASE_URL="https://${CLOUDRON_APP_DOMAIN}"
DRUPAL_BASE_URL="https://${ADMIN_DOMAIN:-}"
DRUSH_OPTIONS_URI="${DRUPAL_BASE_URL}"
if [[ -z "${SESSION_COOKIE_DOMAIN:-}" ]]; then
    SESSION_COOKIE_DOMAIN=$(okb_common_parent "${CLOUDRON_APP_DOMAIN}" "${ADMIN_DOMAIN:-}")
    # ".com" or "" would be rejected by browsers.
    if [[ "${SESSION_COOKIE_DOMAIN}" != .*.* ]]; then
        echo "env.sh: ${CLOUDRON_APP_DOMAIN} and ${ADMIN_DOMAIN:-} share no parent domain; logins will not work across them." >&2
        SESSION_COOKIE_DOMAIN=""
    fi
fi

# --- Database: the mysql addon stands in for the stack's mariadb service ---
MARIADB_HOST="${CLOUDRON_MYSQL_HOST}"
MARIADB_PORT="${CLOUDRON_MYSQL_PORT}"
MARIADB_DATABASE="${CLOUDRON_MYSQL_DATABASE}"
MARIADB_USER="${CLOUDRON_MYSQL_USERNAME}"
MARIADB_PASSWORD="${CLOUDRON_MYSQL_PASSWORD}"

# --- OpenSearch: bundled on loopback unless the operator points elsewhere ---
OPENSEARCH_URL="${OPENSEARCH_URL:-http://127.0.0.1:9200}"
if [[ "${OPENSEARCH_URL}" == "http://127.0.0.1:9200" ]]; then
    OPENKB_BUNDLED_OPENSEARCH=true
else
    OPENKB_BUNDLED_OPENSEARCH=false
fi
OPENSEARCH_JAVA_OPTS="${OPENSEARCH_JAVA_OPTS:--Xms512m -Xmx512m}"
# Cloudron cannot raise vm.max_map_count from inside the container.
OPENSEARCH_ALLOW_MMAP="${OPENSEARCH_ALLOW_MMAP:-false}"
OPENSEARCH_PATH_CONF=/run/opensearch/config
OPENSEARCH_TMPDIR=/tmp/opensearch

# --- Drupal ---
OPENKB_RECIPES_DIR=/app/recipes
PHAPP_ENV_TYPE=docker
PHAPP_ENV_MODE=production
REVERSE_PROXY_ADDRESSES="${CLOUDRON_PROXY_IP:-172.18.0.1}"
OPENAI_API_KEY="${OPENAI_API_KEY:-}"

# --- Frontend (upstream docker/frontend/entrypoint.sh) ---
NODE_ENV=production
NITRO_HOST=0.0.0.0
NITRO_PORT=3000
HOCUSPOCUS_SQLITE=/app/data/collab/hocuspocus.sqlite
NUXT_PUBLIC_DRUPAL_CE_DRUPAL_BASE_URL="${NUXT_PUBLIC_DRUPAL_CE_DRUPAL_BASE_URL:-$DRUPAL_BASE_URL}"
NUXT_DRUPAL_BASE_URL="${NUXT_DRUPAL_BASE_URL:-$DRUPAL_BASE_URL}"
NUXT_PUBLIC_DRUPAL_BASE_URL="${NUXT_PUBLIC_DRUPAL_BASE_URL:-$DRUPAL_BASE_URL}"

# drush and composer want a writable HOME.
HOME=/run/openkb/home
PATH="/app/vendor/bin:/usr/local/node/bin:${PATH}"

set +a
