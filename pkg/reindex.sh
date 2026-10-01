#!/bin/bash
# Recreates every OpenSearch-backed search index on its server and queues all
# items again; cron then indexes them. The OpenSearch data lives in a Cloudron
# persistentDir, which is NOT part of backups (upstream calls the index
# rebuildable), so this runs after a restore. The chunk index re-embeds on the
# next cron runs, which costs embedding API calls when OPENAI_API_KEY is set.
set -eu
source /app/pkg/env.sh
cd /app
[[ "$(id -u)" == 0 ]] && exec gosu www-data:www-data "$0" "$@"

php -d memory_limit=512M ./vendor/drush/drush/drush.php php:eval '
foreach (\Drupal\search_api\Entity\Index::loadMultiple() as $index) {
  if (!$index->status() || !$index->hasValidServer()) {
    continue;
  }
  $server = $index->getServerInstance();
  if ($server->getBackendId() === "search_api_db") {
    continue;
  }
  $backend = $server->getBackend();
  try { $backend->removeIndex($index); } catch (\Throwable $e) {}
  try {
    $backend->addIndex($index);
  }
  catch (\Throwable $e) {
    print "addIndex " . $index->id() . ": " . $e->getMessage() . "\n";
  }
  $index->reindex();
  print "queued " . $index->id() . " (" . $server->id() . ") for reindexing\n";
}'
