# cloud-sql

Cloud SQL for PostgreSQL 17: `db-f1-micro`, Enterprise edition, zonal, 10 GiB SSD, private
address only, TLS required (`ssl_mode = ENCRYPTED_ONLY`), daily backups kept 7 days, point-in-time
recovery off, deletion protection on. It also has the `shiptrack` database, the administrator
`shiptrack_admin`, and connection, disconnection, checkpoint, and lock-wait logging.

The instance name carries a random suffix, because a deleted name cannot be reused for a while.
The administrator's password is a write-only argument: Terraform sends it when
`admin_password_version` changes and stores neither it nor a hash. The application's roles and grants
are created by `deploy-app`'s db-init Job.

Cost: about $10 to $13 a month for the instance **[VERIFY]**, from the moment it is applied. A shared core
has no SLA and a low connection limit. `destroy-cloud-sql` deletes the instance, its data,
and its backups.
