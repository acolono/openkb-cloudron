# OpenKB for Cloudron

[![CI](https://github.com/acolono/openkb-cloudron/actions/workflows/ci.yml/badge.svg)](https://github.com/acolono/openkb-cloudron/actions/workflows/ci.yml)
[![Release](https://github.com/acolono/openkb-cloudron/actions/workflows/release.yml/badge.svg)](https://github.com/acolono/openkb-cloudron/actions/workflows/release.yml)

**Install:** Cloudron dashboard → App Store → *Install community app* →

```
https://github.com/acolono/openkb-cloudron/blob/main/CloudronVersions.json
```

Packages [OpenKB](https://github.com/openkb-app/openkb) (upstream
`quickstart/docker-compose.yml`) as a single Cloudron app.

## Layout

| Upstream compose service | In this package |
|---|---|
| `drupal` (FrankenPHP :8643) | Apache + mod_php on :8080, served on the **Drupal domain** (`ADMIN_DOMAIN` httpPort) |
| `frontend` (Nitro :8642) | node on :3000, the **primary domain**; health check `/api/collab/health` |
| `cron` (supercronic) | `scheduler` addon, `pkg/cron.sh` every 5 min |
| `mariadb` | `mysql` addon (MySQL 8.4) |
| `opensearch` | bundled on 127.0.0.1:9200, data in the `/var/lib/opensearch` persistentDir |

| Upstream volume | Here |
|---|---|
| `drupal-files` | `/app/data/files` (backed up) |
| `collab-store` | `/app/data/collab/hocuspocus.sqlite` (backed up via localstorage `sqlite`) |
| `mariadb-data` | mysql addon (backed up) |
| `opensearch-data` | `/var/lib/opensearch` (**not** backed up; rebuilt by `pkg/reindex.sh`) |

The Drupal code (`/app`) and the built frontend are copied unchanged from the
published `ghcr.io/openkb-app/openkb-{drupal,frontend}` images. Only
`better-sqlite3`'s native binary is rebuilt, because those images are Alpine
and Cloudron's base is Ubuntu.

## Install from source (development)

```sh
cloudron login my.example.com
cloudron install --location kb      # asks for the Drupal domain, e.g. kb-admin
cloudron logs -f                    # first boot installs Drupal (~5 min)
```

Choose the two locations under one parent domain (`kb.example.com` +
`kb-admin.example.com` scopes the session cookie to `.example.com`;
`kb.example.com` + `admin.kb.example.com` scopes it to `.kb.example.com`).

Builds on the server pull ~1.5 GB of upstream images. To build elsewhere, use
`cloudron builder` with a Container Registry app (see the Cloudron tutorial).

## Operating

* Settings: `/app/data/env.sh` (`OPENAI_API_KEY`, OpenSearch heap, external
  OpenSearch). Restart the app after editing.
* Secrets: `/app/data/.secrets.env` (hash salt, collab OAuth client, admin
  password). Generated once; do not edit the collab pair on a live site.
* drush: `cloudron exec -- drush status` (wrapper loads the env, runs as www-data).
* Updates: each new image runs `openkb-update` (updatedb, deploy hooks, config
  import, cache rebuild) once on start. Cloudron backs up before every update.
  Note: upstream never runs updates unattended; this package does, because the
  backup makes it reversible.
* Restore: OpenSearch data is not in the backup. On start, an installed site
  with an empty OpenSearch gets its indexes recreated and requeued; cron then
  re-indexes (re-embedding costs API calls when `OPENAI_API_KEY` is set).
* Memory: default limit 4 GB. Upstream sizes a production host at 8 GB with a
  1 GB+ OpenSearch heap; raise both together.

## Releasing

GitHub Actions does the packaging:

* `ci.yml`, on every push and PR, lints the manifest and scripts and builds the image (no push).
* `release.yml`, on a `vX.Y.Z` tag, builds and pushes
  `ghcr.io/acolono/openkb-cloudron:X.Y.Z`, adds that version to `CloudronVersions.json`
  on `main`, and creates a GitHub release. Installed apps then offer the update.

To release:

1. Bump `version` in `CloudronManifest.json` (and `upstreamVersion` / the
   `OPENKB_TAG` build arg in the `Dockerfile` when following upstream).
2. Add a `[X.Y.Z]` section at the top of `CHANGELOG`.
3. Commit, then `git tag vX.Y.Z && git push origin main --tags`.

To ship a version as "testing" (installable, flagged unstable), run the Release
workflow manually and pick `testing`.

### One-time setup

* **Make the image public.** After the first release, open the package under
  your profile or org → *Packages* → *Package settings* → *Change visibility* →
  Public. Otherwise Cloudron cannot pull it. Alternatively, keep it private and
  add `ghcr.io` with a read-only token under Cloudron → Settings → Docker →
  Private registry.
* **Allow the workflow to push to `main`.** If `main` is protected, allow
  `github-actions[bot]` to bypass, or the catalog commit fails.
