# Modules

Reusable pieces that the roots (`seed`, `data`, `cluster`, `addons`) call. A module holds no provider
configuration, no backend, and no project identifier of its own: the root passes everything in, so a
module can be read, linted, and planned only through the root that uses it.

| Module | Holds | Called by |
|---|---|---|
| [`network`](network) | VPC, subnet, Cloud NAT, private services access | `data` |
| [`cloud-sql`](cloud-sql) | PostgreSQL instance, database, administrator | `data` |
| [`secrets`](secrets) | Database credentials in Secret Manager | `data` |

Each module has `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf` (the provider as a constraint such
as `~> 8.7`; the exact version is pinned in the root), and a short `README.md`.

Planned, one per resource group of the destroy workflows (ADR-0027), each added in the pull request that
builds it: `pubsub`, `proof-of-delivery-storage`, `monitoring`, and `workload-access` (one workload's IAM
bindings, design §7.3).
