# terraform/data

The network, and (added by later increments) Cloud SQL, Pub/Sub, the proof-of-delivery bucket,
Secret Manager, and the workload bindings. Design: `docs/DESIGN.md` §8.2.

| File | Holds |
|---|---|
| `network.tf` | VPC, subnet with secondary ranges for pods and services, router and Cloud NAT, and the range and peering for private services access (ADR-0007) |
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
- **destroy-network** takes the network down again, after two approvals and the typed name `network`.
  Remove Cloud SQL and the cluster first.

The network has a small fixed cost once applied: Cloud NAT is about $4 to $6 a month even with no
traffic **[VERIFY]**. Everything else here is free until it is used.

State is `gcp/data/default.tfstate` in the state bucket. `backend.tf` is written at run time and never
committed.
