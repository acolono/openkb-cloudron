#!/bin/bash
# The scheduler addon's task, every five minutes: upstream's `cron` service.
# Runs in a short-lived container from this image, sharing the app's network
# namespace, /app/data and /run.
set -eu
source /app/pkg/env.sh
exec gosu www-data:www-data /usr/local/bin/openkb-cron
