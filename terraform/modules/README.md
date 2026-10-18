# Modules

Reusable pieces that the roots (`seed`, `data`, `cluster`, `addons`) call. A module holds no provider
configuration, no backend, and no project identifier of its own: the root passes everything in, so a
module can be read, linted, and planned only through the root that uses it.

| Module | Holds | Called by |
|---|---|---|
| [`network`](network) | VPC, subnet, Cloud NAT, private services access | `data` |
| [`cloud-sql`](cloud-sql) | PostgreSQL instance, database, administrator | `data` |
| [`secrets`](secrets) | Database credentials in Secret Manager | `data` |
| [`pubsub`](pubsub) | Event and notification topics, subscriptions, dead letters | `data` |
| [`proof-of-delivery-storage`](proof-of-delivery-storage) | The proof-of-delivery bucket and the signer's read access | `data` |
| [`monitoring`](monitoring) | The alert policies, the notification channel, the SLA heartbeat metric, and the dashboard | `data` |
| [`gke-autopilot`](gke-autopilot) | The GKE Autopilot cluster | `cluster` |
| [`ui-ingress`](ui-ingress) | The proxy-only subnet, the reserved address, and the Cloud Armor policy for the UI's load balancer | `data` |
| [`workload-access`](workload-access) | One workload's IAM bindings on the resources it uses | `cluster` |

Each module has `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf` (the provider as a constraint such
as `~> 8.7`; the exact version is pinned in the root), and a short `README.md`.

