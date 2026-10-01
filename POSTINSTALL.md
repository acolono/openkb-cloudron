The first start installs the Drupal site in the background, which takes a few
minutes. Until it is done, both domains show a "setting up" page.

* **Site:** $CLOUDRON-APP-ORIGIN
* **Admin:** the Drupal domain you chose, at `/user/login`, user `admin`

The admin password was generated on first start:

```
cloudron exec --app $CLOUDRON-APP-FQDN -- grep ADMIN_PASSWORD /app/data/.secrets.env
```

AI chat and semantic search need `OPENAI_API_KEY` in `/app/data/env.sh`.
