# Secret rotation

**Use it** to change the database passwords. They are generated for one run and written with write-only
arguments, so no value is in state, a plan, or a log. The application keeps the credentials it fetched until
a database login fails, then fetches once more.

1. Pull request: raise `db_credentials_version` in `terraform/data/variables.tf` by one. The plan shows
   changes to the secret versions and the Cloud SQL administrator password; it never shows a value.
2. After the merge, **apply-terraform**, root `data`, approve `dev`. New passwords are in Secret Manager.
3. Right away, **deploy-app** with the digest already running. Its `db-init` Job sets the `shiptrack_app` and
   `shiptrack_migrator` roles to the new passwords. Until it finishes, a pod that starts fetches the new
   password and cannot log in, and a running pod keeps working on the old one.
4. The pods that hold an old connection fetch the new password the next time a login fails. Nothing restarts.

## Check
- `ops-contract` passes.
- No alert fires, and the dashboard's database connection tile stays steady.

**Tested:** not yet. It changes the live database passwords, so it is run once on purpose, not as a side effect.
