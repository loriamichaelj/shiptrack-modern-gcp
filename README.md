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
.github/workflows/
  apply-seed.yml        applies terraform/seed
  ci-checks.yml         pull request checks: terraform, secrets, workflows
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
| G8 Workflows | Partly: `ci-checks` and `apply-seed` are built. `ci-terraform`, `apply-terraform`, `deploy-app`, `ops-contract`, and the `destroy-` workflows are not. The `dev` and `ci` environments hold no secrets yet |
| G1 to G3 Application seam, chart, image (in `shiptrack-modern`) | Not started |
| G5 to G7 Data, cluster, and addons roots | Not started |
| G9 to G11 Application, validation, operations | Not started |

Decisions still waiting on the user are the entries marked Planned in [`docs/ADR.md`](docs/ADR.md),
chiefly Spot pods (ADR-0005) and no public ingress (ADR-0013). They gate the data and cluster roots.

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
