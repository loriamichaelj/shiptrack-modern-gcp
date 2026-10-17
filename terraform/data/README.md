# terraform/data

The network, Cloud SQL, the database credentials, Pub/Sub, and the proof-of-delivery bucket. Workload
bindings follow the cluster. Design: `docs/DESIGN.md`.

| File | Holds |
|---|---|
| `main.tf` | The `network` module (`../modules/network`): VPC, subnet with secondary ranges for pods and services, router and Cloud NAT, and the range and peering for private services access |
| `main.tf` (cont.) | The `cloud_sql`, `secrets`, `pubsub`, and `proof_of_delivery_storage` modules, in `../modules` |
| `main.tf` (cont.) | The `ui_ingress` module: the proxy-only subnet, address, and Cloud Armor policy the UI's load balancer needs. The Gateway itself is applied by `deploy-app` |
| `credentials.tf` | The database passwords, as ephemeral values: generated for one run, never stored |
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
- **destroy-network**, **destroy-cloud-sql**, **destroy-secrets**, **destroy-pubsub**, and
  **destroy-proof-of-delivery-storage**, and **destroy-ingress** take a group down again, after two approvals and the typed name.
  Remove the cluster first, then Cloud SQL, then the network. `destroy-cloud-sql` deletes the data and the
  backups, and `destroy-proof-of-delivery-storage` deletes every stored document.

Cost once applied **[VERIFY]**: Cloud SQL about $10 to $13 a month, Cloud NAT about $4 to $6 even with no
traffic. Secret Manager, Pub/Sub, and the bucket are free at this size.

`deletion_protection` (default true) protects Cloud SQL, and `proof_of_delivery_protection` the bucket. Only
their destroy workflows lower them, inside an approved run; a normal apply sets them back. `db_credentials_version` rotates the passwords.

State is `gcp/data/default.tfstate` in the state bucket. `backend.tf` is written at run time and never
committed.
