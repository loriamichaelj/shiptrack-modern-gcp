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
| `terraform/data/` | The network, Cloud SQL, the database secrets, Pub/Sub, the proof-of-delivery bucket, the UI's ingress objects, and the alerts and dashboard |
| `terraform/cluster/` | The GKE Autopilot cluster and the workloads' IAM bindings |
| `terraform/addons/` | The `shiptrack` namespace and the deploy account's role in it |
| `terraform/finops/` | The monthly budget with alerts, and the dataset for the billing export |
| `deploy/` | The Helm values, the pinned chart commit, the db-init Job, `gateway/` (the UI's load balancer), and `validation/` (the check Jobs of `ops-validate`) |
| `terraform/modules/` | The pieces the roots call: network, cloud-sql, secrets, pubsub, proof-of-delivery-storage, ui-ingress, monitoring, gke-autopilot, workload-access |
| `.github/workflows/` | `apply-seed`, `apply-terraform`, `ci-checks`, `ci-terraform`, a `destroy-` workflow per cost-bearing group, `deploy-app`, and the `ops-` workflows: `ops-contract`, `ops-validate`, `ops-queues`, `ops-restart`, `ops-reset-data`, `ops-ui-port`, and the read-only `ops-check-cluster`, `ops-check-cost`, `ops-check-state`, `ops-check-metrics`, and `ops-check-logs` |
| `scripts/` | The chart arguments, the connection budget check, the rollout sampler, the contract and validation runs through a port-forward, `queues.sh` for the dead-letter queues, and `ui-access.sh`, which opens and closes the browser URL from your machine |
| `docs/runbooks/` | One page per situation: deploy and rollback, dead-letter redrive, secret rotation, state recovery, and one per alert. Each records when it was tested |
| `.github/scripts/` | The plan, apply, and destroy wrappers, which print addresses and actions only, and the cost report |

## Status

The stack is built, applied, and running the same image digest as AWS. What is proven, and what is not, is below.

| Area | State |
|---|---|
| Design | Done |
| Application changes in `shiptrack-modern` | Done and merged: the cloud seam, the chart switches, the GHCR image publish, the `db-init` command, the network policy that admits the managed Prometheus collectors, and the secret refetch after a rejected login |
| Seed, data, cluster, add-ons | Done and applied; the deploy account reaches the cluster and only its own namespace |
| FinOps | Budget alerts and the cost export are in place. The export had no rows on 18 October, so there is no cost analysis yet |
| Release | Deployed by `deploy-app`; the full contract suite passes through a port-forward |
| UI | A browser URL through a regional load balancer, open to one address, plain HTTP |
| Monitoring | Applied: eight alerts, a notification channel, and a dashboard. Metrics reach Managed Prometheus. The dashboard shows an update in every plan, which is not fixed |
| Validation | Passed: no event lost across a rollout or across every pod being deleted under load (1208 of 1208 events stored, twice); one SLA alert per breached shipment, on a small sample (2 shipments) |
| Runbooks | Written. The dead-letter one is tested end to end; deploy and state recovery in part; secret rotation found a defect in the application, now fixed, and is not yet re-run; the others are not tested as responses to an alert |
| Dependabot | Not set up here, though the design lists it |

### Acceptance criteria

| # | Criterion | State |
|---|---|---|
| 1 | One digest in ECR and GHCR, and GCP runs it | Done |
| 2 | One image on every cloud, AWS and Azure unchanged | Done, except that the secret refetch fix improves AWS behavior, as recorded in the decisions of `shiptrack-modern` |
| 3 | Every resource except the by-hand seed comes from Terraform applied by a workflow | Done |
| 4 | No service account key, no Kubernetes Secret holding a credential, no identifier in git | Done |
| 5 | The contract `full` suite passes through a port-forward | Done |
| 6 | Zero lost events across a deploy and a Spot preemption | Done: the pod side of both, tested by restarting and deleting pods under load |
| 7 | Exactly one `sla_alerts` row per breached shipment | Done on a small sample |
| 8 | `/ui/` is served with the security headers and the `modern` badge | Partly checked: the page answers and the stack header says `modern`; the other headers and the badge are not checked |
| 9 | Every resource carries `environment: dev` and `name: shiptrack` | Done for every resource that can carry them; the regional Cloud Armor policy and the Gateway's forwarding rule cannot, as recorded in the decisions |
| 10 | Baseline cost within the design's range, or explained | Not done: the billing export has no rows yet |
| 11 | The four named runbooks exist and are tested once | Partly: dead-letter is done; rollback, secret rotation, and the state restore are not |
| 12 | Every cost-bearing group has a destroy workflow, and each was run once | The workflows exist; none has been run |

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
