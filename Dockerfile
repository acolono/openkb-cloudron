# OpenKB for Cloudron: the whole upstream compose stack in one container.
#
#   upstream service      here
#   drupal (FrankenPHP)   Apache + mod_php on :8080      (ADMIN_DOMAIN)
#   frontend (Nitro)      node on :3000                  (primary domain)
#   cron (supercronic)    Cloudron scheduler addon -> pkg/cron.sh
#   mariadb               Cloudron mysql addon
#   opensearch            bundled, 127.0.0.1:9200, data in a persistentDir
#
# The Drupal code and the built frontend are taken verbatim from the published
# images. Only the frontend's one native addon (better-sqlite3) is rebuilt,
# because the upstream images are Alpine (musl) and this base is Ubuntu (glibc).

ARG OPENKB_TAG=1.0.0-beta2
# Pin this before production use; upstream's compose floats on `3`.
ARG OPENSEARCH_TAG=3
ARG BASE_IMAGE=cloudron/php-base:8.4-20260920@sha256:e9352b5fba7ad0a231b8a9e454034400a3a34a7fe1800425f634d32ffcae4a52

FROM ghcr.io/openkb-app/openkb-drupal:${OPENKB_TAG} AS upstream-drupal
FROM ghcr.io/openkb-app/openkb-frontend:${OPENKB_TAG} AS upstream-frontend
FROM opensearchproject/opensearch:${OPENSEARCH_TAG} AS upstream-opensearch

# ---------------------------------------------------------------- node 22 LTS
# The frontend is built and tested on node 22; php-base ships no node.
FROM ${BASE_IMAGE} AS node
ARG NODE_MAJOR=22
RUN set -eux; \
    base="https://nodejs.org/dist/latest-v${NODE_MAJOR}.x"; \
    curl -fsSL "$base/SHASUMS256.txt" -o /tmp/SHASUMS256.txt; \
    tarball=$(awk '/linux-x64\.tar\.gz$/ {print $2}' /tmp/SHASUMS256.txt); \
    curl -fsSL "$base/$tarball" -o "/tmp/$tarball"; \
    (cd /tmp && grep " $tarball\$" SHASUMS256.txt | sha256sum -c -); \
    mkdir -p /usr/local/node; \
    tar -xzf "/tmp/$tarball" -C /usr/local/node --strip-components=1; \
    rm -f /tmp/*.tar.gz /tmp/SHASUMS256.txt; \
    /usr/local/node/bin/node --version

# ------------------------------------------- frontend, native addon for glibc
FROM node AS frontend
ENV PATH=/usr/local/node/bin:$PATH
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 make g++ \
 && rm -rf /var/lib/apt/lists/*
COPY --from=upstream-frontend /app/frontend /app/frontend
RUN set -eux; \
    server=/app/frontend/.output/server; \
    pkgdir=$(dirname "$(find "$server/node_modules" -path '*/better-sqlite3/package.json' | head -n1)"); \
    version=$(node -p "require('$pkgdir/package.json').version"); \
    mkdir /tmp/bs; cd /tmp/bs; npm init -y >/dev/null; \
    npm install --no-audit --no-fund --omit=dev "better-sqlite3@$version"; \
    find /app/frontend/.output -name better_sqlite3.node -print \
      -exec cp /tmp/bs/node_modules/better-sqlite3/build/Release/better_sqlite3.node {} \; ; \
    node -e "const D = require('$pkgdir'); new D(':memory:').prepare('select 1').get()"; \
    others=$(find /app/frontend/.output -name '*.node' ! -name better_sqlite3.node); \
    if [ -n "$others" ]; then echo "musl-only native addons left: $others" >&2; exit 1; fi; \
    rm -rf /tmp/bs /root/.npm

# ---------------------------------------------------------------------- final
FROM ${BASE_IMAGE}
ARG OPENKB_TAG
ARG PHP_SERIES=8.4

# PHP extensions the upstream image installs (apcu gd intl opcache pdo_mysql
# pdo_pgsql zip), plus libgomp1 for OpenSearch's k-NN native libraries.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      php${PHP_SERIES}-apcu php${PHP_SERIES}-gd php${PHP_SERIES}-intl \
      php${PHP_SERIES}-mysql php${PHP_SERIES}-pgsql php${PHP_SERIES}-zip \
      php${PHP_SERIES}-mbstring php${PHP_SERIES}-xml php${PHP_SERIES}-curl \
      libgomp1; \
    rm -rf /var/lib/apt/lists/*; \
    for m in apcu gd intl pdo_mysql pdo_pgsql zip mbstring 'Zend OPcache'; do \
      php -m | grep -qix "$m" || { echo "PHP extension missing: $m" >&2; exit 1; }; \
    done; \
    for c in mysql gosu supervisord flock openssl curl; do command -v "$c"; done

# Apache: one vhost on :8080, errors to stderr, no access log (Cloudron's
# proxy keeps one), prefork for mod_php.
COPY conf/apache-openkb.conf /etc/apache2/sites-available/openkb.conf
RUN set -eux; \
    rm -f /etc/apache2/sites-enabled/*; \
    sed -e 's,^ErrorLog.*,ErrorLog "/dev/stderr",' -i /etc/apache2/apache2.conf; \
    echo 'ServerName localhost' > /etc/apache2/conf-available/servername.conf; \
    a2enconf servername; \
    a2disconf other-vhosts-access-log || true; \
    echo 'Listen 8080' > /etc/apache2/ports.conf; \
    a2dismod -f mpm_event mpm_worker 2>/dev/null || true; \
    a2enmod mpm_prefork rewrite headers alias; \
    a2enmod "php${PHP_SERIES}"; \
    a2ensite openkb

# Supervisor logs into /run (read-only filesystem).
RUN sed -e 's,^logfile=.*$,logfile=/run/supervisord.log,' -i /etc/supervisor/supervisord.conf
COPY conf/supervisor-openkb.conf /etc/supervisor/conf.d/openkb.conf

# --- Drupal: the published image's /app, unchanged ---
COPY --from=upstream-drupal /app /app
COPY --from=upstream-drupal \
     /usr/local/bin/openkb-boot /usr/local/bin/openkb-install \
     /usr/local/bin/openkb-update /usr/local/bin/openkb-cron \
     /usr/local/bin/
COPY --from=upstream-drupal /usr/local/share/openkb/holding.html /usr/local/share/openkb/holding.html
COPY --from=upstream-drupal /usr/local/etc/php/conf.d/zz-openkb.ini /tmp/zz-openkb.ini
COPY conf/settings.local.php /app/web/sites/default/settings.local.php
RUN set -eux; \
    for sapi in apache2 cli; do \
      cp /tmp/zz-openkb.ini /etc/php/${PHP_SERIES}/$sapi/conf.d/99-openkb.ini; \
    done; \
    rm /tmp/zz-openkb.ini; \
    # /app/files is the upstream `drupal-files` volume: public, private,
    # config sync, OAuth keys. web/files and config/sync already point into it.
    mv /app/files /app/files.dist; \
    ln -s /app/data/files /app/files

# --- Frontend ---
COPY --from=node /usr/local/node /usr/local/node
COPY --from=frontend /app/frontend /app/frontend
RUN rm -rf /app/frontend/var && ln -s /app/data/collab /app/frontend/var

# --- OpenSearch, reduced to the four plugins upstream keeps ---
COPY --from=upstream-opensearch /usr/share/opensearch /usr/share/opensearch
RUN set -eux; \
    cd /usr/share/opensearch; \
    keep=" opensearch-knn opensearch-neural-search opensearch-custom-codecs opensearch-system-templates "; \
    for p in $(ls plugins); do \
      case "$keep" in *" $p "*) ;; *) rm -rf "plugins/$p" "config/$p" "bin/$p" ;; esac; \
    done; \
    ls plugins; \
    # jvm.options writes relative to OPENSEARCH_HOME, which is read-only here.
    sed -i \
      -e 's,file=logs/gc.log,file=/run/opensearch/logs/gc.log,' \
      -e 's,HeapDumpPath=data,HeapDumpPath=/tmp/opensearch,' \
      -e 's,ErrorFile=logs/,ErrorFile=/run/opensearch/logs/,' \
      config/jvm.options

# --- Package scripts ---
COPY pkg/ /app/pkg/
COPY start.sh /app/pkg/start.sh
RUN set -eux; \
    chmod +x /app/pkg/*.sh /app/pkg/drush /app/pkg/start.sh; \
    ln -s /app/pkg/drush /usr/local/bin/drush; \
    echo "${OPENKB_TAG}" > /app/pkg/UPSTREAM_VERSION; \
    # Changes with every image, so boot.sh knows to run openkb-update once.
    date -u +%Y%m%d%H%M%S > /app/pkg/BUILD_ID

# /app/vendor/bin is deliberately not on the image PATH: pkg/env.sh adds it for
# the app's own processes, so in a `cloudron exec` shell `drush` resolves to the
# pkg/drush wrapper, which loads the environment and drops to www-data.
ENV PATH=/usr/local/node/bin:$PATH
WORKDIR /app
EXPOSE 3000 8080

CMD [ "/app/pkg/start.sh" ]
