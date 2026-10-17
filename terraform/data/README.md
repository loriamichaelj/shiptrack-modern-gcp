# terraform/data

The network, Cloud SQL, and the database credentials, and (added by later increments) Pub/Sub, the
proof-of-delivery bucket, and the workload bindings. Design: `docs/DESIGN.md` §8.2.

| File | Holds |
|---|---|
| `main.tf` | The `network` module (`../modules/network`): VPC, subnet with secondary ranges for pods and services, router and Cloud NAT, and the range and peering for private services access (ADR-0007) |
| `main.tf` (cont.) | The `cloud_sql` module (`../modules/cloud-sql`) and the `secrets` module (`../modules/secrets`) |
| `credentials.tf` | The database passwords, as ephemeral values: generated for one run, never stored (ADR-0017) |
| `outputs.tf` | Names the other roots look resources up by. Nothing here is secret, and no workflow prints it |

## Running it

Before the first run, give the `ci` and `dev` environments their secrets (`terraform/seed/README.md`,
"Wiring the other workflows").

- A pull request that changes this root runs **ci-terraform** after you approve the `ci` environment. It
  plans as `shiptrack-plan`, which cannot change anything, and comments the addresses and actions.
  Before the first apply there is no state object, and the read-only account cannot create one, so the
  plan runs against empty state and shows every resource as a create.
- After the merge, Actions, **apply-terraform**, root `data`, on `dev`. Approve the `dev` environment. The
  run plans again and applies that plan; the log lists addresses and actions, never values.
- **destroy-network**, **destroy-cloud-sql**, and **destroy-secrets** take a group down again, after two
  approvals and the typed name (`network`, `cloud-sql`, `secrets`). Remove the cluster first, then Cloud SQL,
  then the network. `destroy-cloud-sql` deletes the data and the backups.

Cost once applied **[VERIFY]**: Cloud SQL about $10 to $13 a month, Cloud NAT about $4 to $6 even with no
traffic, Secret Manager nothing at this size.

`deletion_protection` (default true) protects Cloud SQL. Only `destroy-cloud-sql` lowers it, inside its
approved run; a normal apply sets it back. `db_credentials_version` rotates the passwords.

State is `gcp/data/default.tfstate` in the state bucket. `backend.tf` is written at run time and never
committed.
