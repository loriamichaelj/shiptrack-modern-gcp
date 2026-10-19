# Secret rotation

**Use it** to change the database passwords. They are generated for one run and written with write-only
arguments, so no value is in state, a plan, or a log. A pod keeps the credentials it fetched. When the server
turns a new login down, the application fetches the secret once more and tries again. That only works in an
image that has the fix of `shiptrack-modern` PR 66; an older image keeps the old password until it restarts.

1. Pull request: raise `db_credentials_version` in `terraform/data/variables.tf` by one. The plan shows
   changes to the secret versions and the Cloud SQL administrator password; it never shows a value. The old
   secret versions are destroyed, so there is no way back to the old passwords.
2. After the merge, **apply-terraform**, root `data`, approve `dev`. New passwords are in Secret Manager.
3. Right away, **deploy-app** with the digest already running. Its `db-init` Job sets the `shiptrack_app` and
   `shiptrack_migrator` roles to the new passwords. Until it finishes, a pod that starts fetches the new
   password and cannot log in (the SLA scan fails in this gap), and a running pod keeps working on the old one.
4. Pods with the fix fetch the new password on their next new connection. Nothing restarts. With an image
   without the fix, run **ops-restart**: every pod restarts and fetches the current password at startup.

## Check
- `ops-contract` passes.
- `ops-check-logs` shows no `database_unavailable` or `unhandled_error` records after `db-init` finished.
- No alert fires, and the dashboard's database connection tile stays steady.

**Tested:** once, on 2026-10-18, with an image that lacked the fix. The apply and `db-init` worked, and the SLA scan
failed in the gap as described. The api returned 500 and 503 on every request that needed a new connection, because
the application never fetched the secret again after a rejected login. `ops-restart` brought it back. The defect is
fixed (`shiptrack-modern` PR 66) and its image is deployed, but the rotation has not been run again with it, so the
no-restart behavior of step 4 is not yet proven.
