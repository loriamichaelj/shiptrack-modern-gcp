# secrets

Three Secret Manager secrets, `shiptrack-db-app`, `shiptrack-db-migrator`, and `shiptrack-db-admin`. Each
holds a JSON document with the shape of the AWS secret (`username`, `password`, `host`, `port`, `dbname`,
`engine`), so the application reads it the same way.

The passwords are ephemeral values generated for one run and written with a write-only argument, so no
value is in state, a plan, or a log. They are written when `credentials_version` changes. To
rotate, raise `db_credentials_version` in the `data` root, apply, and run db-init again so the database
roles take the new passwords.

Cost: Secret Manager's free tier covers six active versions and 10,000 accesses a month, and this
holds three. `destroy-secrets` removes them.
