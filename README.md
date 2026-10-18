# ShipTrack Modern GCP

Runs [`shiptrack-modern`](https://github.com/loriamichaelj/shiptrack-modern) on Google Cloud, next to its
AWS and Azure homes. The same image digest runs on all three clouds. This repository holds only GCP
infrastructure (Terraform), GitHub workflows, GCP Helm values, and docs. The application code stays in
`shiptrack-modern`, and nothing here changes how it behaves on AWS or Azure.

In the cloud migration this is a **replatform** of the target workload onto a second cloud, one of the 7 Rs
that AWS Prescriptive Guidance defines
([About the migration strategies](https://docs.aws.amazon.com/prescriptive-guidance/latest/large-migration-guide/migration-strategies.html)):
the application is unchanged, and each concern moves to the matching managed GCP service.

- Design: [`docs/DESIGN.md`](docs/DESIGN.md)
- Decisions: [`docs/ADR.md`](docs/ADR.md)

## What it builds

| Concern | GCP service |
|---|---|
| Orchestration | GKE Autopilot in `us-central1`, private nodes, Spot pods |
| Database | Cloud SQL for PostgreSQL, shared-core, private IP only |
| Queues and events | Pub/Sub topics and pull subscriptions, with dead-letter topics |
| Proof-of-delivery storage | Cloud Storage with V4 signed URLs through the IAM signing API |
| Secrets | Secret Manager, read by each pod through Workload Identity for GKE |
| Egress | Cloud NAT |
| Delivery | `deploy-app` workflow: Helm with `--atomic`, after environment approval |
| Observability | Managed Service for Prometheus, Cloud Logging, Cloud Monitoring |

There is no public ingress by default (a demo runs through `kubectl port-forward`), and cost is a design
constraint: about $25 to $35 a month for the baseline, watched by a $75 budget with alerts.

## How changes reach GCP

All infrastructure changes run through GitHub Actions with GitHub OIDC and Workload Identity Federation.
There are no service account keys anywhere, and every apply waits for the owner's approval in one of three
environments: `seed` (`apply-seed` creates the state bucket, the service accounts, and their trust), `ci`
(pull request checks and read-only plans), and `dev` (Terraform applies and deploys).

Five Terraform roots: `seed`, then `data`, `cluster`, and `addons`, plus `finops` (the budget and cost
export), which is separate so that taking the others down keeps the cost history.

## Layout

| Path | What it holds |
|---|---|
| `terraform/seed/` | State bucket, APIs, service accounts, GitHub trust, permissions. Setup steps are in its README |
| `terraform/data/` | The network, Cloud SQL, the database secrets, Pub/Sub, and the proof-of-delivery bucket |
| `terraform/cluster/` | The GKE Autopilot cluster and the workloads' IAM bindings |
| `terraform/addons/` | The `shiptrack` namespace and the deploy account's role in it |
| `terraform/finops/` | The monthly budget with alerts, and the dataset for the billing export |
| `deploy/` | The Helm values, the pinned chart commit, the db-init Job, and `gateway/`, the objects of the UI's load balancer |
| `terraform/modules/` | The pieces the roots call: network, cloud-sql, secrets, pubsub, proof-of-delivery-storage, ui-ingress, gke-autopilot, workload-access |
| `.github/workflows/` | `apply-seed`, `apply-terraform`, `ci-checks`, `ci-terraform`, a `destroy-` workflow per cost-bearing group, `deploy-app`, `ops-contract`, `ops-validate`, `ops-queues`, `ops-check-state`, `ops-ui-port`, `ops-check-cluster`, and `ops-check-cost` |
| `scripts/` | The chart arguments, the connection budget check, the rollout sampler, the contract run through a port-forward, and `ui-access.sh`, which opens and closes the browser URL from your machine |
| `.github/scripts/` | The plan, apply, and destroy wrappers, which print addresses and actions only, and the cost report |

## Status

| Area | State |
|---|---|
| Design | Done |
| Application changes in `shiptrack-modern` | Done and merged: the cloud seam, the chart switches, the GHCR image publish, and the `db-init` command |
| Seed (state bucket, service accounts, trust) | Done and applied |
| Data, cluster, and add-ons | Done and applied; the deploy account reaches the cluster and only its own namespace |
| FinOps | Done: the budget alerts, the cost export, and `ops-check-cost` |
| Workflows | All built |
| First release | `deploy-app` has run: db-init, the migration, the Helm install, and the contract smoke suite passed on the first dispatch. The full contract suite (`ops-contract`) then passed |
| Deploy files | Built: the Helm values, the pinned chart, the db-init Job, and a pull request check that renders and scans them |
| Monitoring | Built: alert policies, the notification channel, and a dashboard in the `data` root; `destroy-monitoring` |
| Validation | Built: `ops-validate` (event loss across a deploy and a pod reclaim, and the SLA alert check). Not run yet |
| Operations | Runbooks and `ops-queues` built, not yet tested. Still to do: the cost analysis, and a run of each destroy workflow |

## Opening the UI in a browser

The application has no public address until you ask for one, and then only your own address can reach it.
`kubectl port-forward` always works (see below). For a URL in a browser, from one address:

```sh
scripts/ui-access.sh open     # sets the allow-list to your current address and dispatches ops-ui-port open
scripts/ui-access.sh url      # prints http://<address>/ui/
scripts/ui-access.sh close    # admits nobody; the load balancer is still billed
scripts/ui-access.sh remove   # deletes the load balancer and stops its charge
```

Approve the `dev` environment in GitHub when a run waits. The first `open` creates the load balancer and takes several
minutes. Your address is kept in a masked secret, never in a workflow input, because inputs are public. The URL is plain
HTTP, so what you do in the UI is not encrypted; the allow-list keeps everyone else out. The load balancer adds about
$24 a month while it exists.

Without a load balancer: `kubectl -n shiptrack port-forward svc/shiptrack-api 8000:8000`, then
`http://localhost:8000/ui/`.

## Getting started

The one-time setup (Workload Identity pool and provider, the seed service account, GitHub environments,
secrets) and the first `apply-seed` run are in [`terraform/seed/README.md`](terraform/seed/README.md).

## Public repository

This repository is public. It never contains the project ID or number, organization, folder, or billing
account IDs, service account emails, Workload Identity pool or provider names, bucket names, or the
cluster endpoint. Those live in GitHub secrets and are masked in workflow logs. Examples use
placeholders such as `<PROJECT_ID>`.

## Related repositories

| Repository | Purpose |
|---|---|
| `shiptrack-platform` | Shared AWS infrastructure, the cutover control point, validation tooling |
| `shiptrack-legacy` | The source stack: the application being migrated |
| `shiptrack-modern` | The target stack: the application and Helm chart |
| `shiptrack-modern-azure` | The Azure target |
