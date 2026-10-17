# ShipTrack Modern GCP

Runs [`shiptrack-modern`](https://github.com/loriamichaelj/shiptrack-modern) on Google Cloud, next to its
AWS and Azure homes. The same image digest runs on all three clouds. This repository holds only GCP
infrastructure (Terraform), GitHub workflows, GCP Helm values, and docs. The application code stays in
`shiptrack-modern`, and nothing here changes how it behaves on AWS or Azure.

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

There is no public ingress by default, and cost is a design constraint: about $25 to $35 a month for the
baseline. The full service mapping, architecture, and cost table are in [`docs/DESIGN.md`](docs/DESIGN.md).

## How changes reach GCP

All infrastructure changes run through GitHub Actions with GitHub OIDC and Workload Identity Federation.
There are no service account keys anywhere, and every apply waits for environment approval.

| Environment | Used by |
|---|---|
| `seed` | `apply-seed`: creates the state bucket, the service accounts, their trust, and their permissions |
| `ci` | Pull request checks: static checks and read-only Terraform plans |
| `dev` | Terraform applies and application deploys |

Every workflow job runs in one of these environments, and each needs the repository owner's approval.

Four Terraform roots, applied in this order: `seed`, `data`, `cluster`, `addons`.

## Layout

```
docs/
  DESIGN.md             the spec
  ADR.md                decisions
terraform/
  seed/                 state bucket, APIs, service accounts, GitHub trust, permissions
    scripts/            ci.sh (plan and apply), github-setup.sh (environments, branch protection)
  data/                 the network, Cloud SQL, and the database secrets (Pub/Sub and storage follow)
  modules/              network, cloud-sql, secrets (more follow with the resources they hold)
  finops/               the monthly budget with alerts, and the dataset for the billing export
.github/workflows/
  apply-seed.yml        applies terraform/seed
  ci-checks.yml         pull request checks: terraform, secrets, workflows
  ci-terraform.yml      pull request plan of the data, cluster, and addons roots, as a comment
  apply-terraform.yml   applies one of those roots (and finops)
  destroy-network.yml   takes the network down
  destroy-cloud-sql.yml takes the database down
  destroy-secrets.yml   takes the database secrets down
  check-cost.yml        the month's cost from the billing export, read-only
.github/scripts/        terraform-ci.sh (plan and apply a root), terraform-destroy.sh (destroy one group), cost-report.sh (the cost report)
.checkov.yaml           checkov configuration
.gitleaks.toml          secret scanning configuration
.tflint.hcl             tflint configuration
```

The `data`, `cluster`, and `addons` roots, the CI and deploy workflows, and the Helm values are described
in the design and are added phase by phase.

## Status

| Phase | State |
|---|---|
| G0 Design | Done: `docs/DESIGN.md` and `docs/ADR.md` |
| G4 Seed | Done and applied: `apply-seed` ran twice, and the second run ended with "No changes". The state bucket, the five service accounts, and their trust exist. `dev` is protected, and the `seed` environment holds its secrets |
| G8 Workflows | Partly: `ci-checks`, `apply-seed`, `ci-terraform`, `apply-terraform`, and the `destroy-` workflows for the network, Cloud SQL, and secrets are built. `deploy-app`, `ops-contract`, and the other `destroy-` workflows are not. The `ci` and `dev` environments hold their secrets |
| G1 Application seam (in `shiptrack-modern`) | Done: `SHIPTRACK_CLOUD`, the GCP backends, and their emulator tests are merged (modern ADR-0032) |
| G2 Chart switches (in `shiptrack-modern`) | Built and in review: `cloud`, `scaling.mode`, `spot`, the `gcp` block, and `PodMonitoring` (modern ADR-0033) |
| G3 Image (in `shiptrack-modern`) | Not started |
| G5 Data root | In progress: the network, Cloud SQL, and the database secrets are built and not yet applied. Pub/Sub, the bucket, and the workload bindings follow |
| G6 to G7 Cluster and addons roots | Not started |
| FinOps (ADR-0028) | Done: the $50 budget with alerts, the email channel, and the export dataset are applied, and the usage cost export is on. `check-cost` reads it |
| G9 to G11 Application, validation, operations | Not started |

Decisions still waiting on the user are the entries marked Planned in [`docs/ADR.md`](docs/ADR.md),
such as the network, database, and observability choices. They gate the data and cluster roots.

Phases are applied in order. The phase table in [`docs/DESIGN.md`](docs/DESIGN.md) §16 gives each
phase's "Done when".

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
| `shiptrack-legacy` | The "before" stack |
| `shiptrack-modern` | The application and Helm chart |
| `shiptrack-modern-azure` | The Azure target |
