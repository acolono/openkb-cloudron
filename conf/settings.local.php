<?php

/**
 * @file
 * Cloudron overrides. web/sites/default/settings.php includes this file last.
 */

// The mysql addon (MySQL 8.4) stands in for upstream's MariaDB, which the
// compose stack starts with --transaction-isolation=READ-COMMITTED.
$databases['default']['default']['init_commands']['isolation_level'] =
  'SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED';

// The image is read-only: never chmod sites/default, keep compiled Twig/PHP
// out of the backed-up files directory.
$settings['skip_permissions_hardening'] = TRUE;
$settings['file_temp_path'] = '/tmp';
$settings['php_storage']['default']['directory'] = '/run/openkb/php';

// Outgoing mail through the sendmail addon's relay, with core's Symfony
// Mailer plugin.
if ($smtp_host = getenv('CLOUDRON_MAIL_SMTP_SERVER')) {
  $config['system.mail']['interface']['default'] = 'symfony_mailer';
  $config['system.mail']['mailer_dsn'] = [
    'scheme' => 'smtp',
    'host' => $smtp_host,
    'port' => (int) getenv('CLOUDRON_MAIL_SMTP_PORT'),
    'user' => getenv('CLOUDRON_MAIL_SMTP_USERNAME'),
    'password' => getenv('CLOUDRON_MAIL_SMTP_PASSWORD'),
    'options' => [],
  ];
  $config['system.site']['mail'] = getenv('CLOUDRON_MAIL_FROM');
}
