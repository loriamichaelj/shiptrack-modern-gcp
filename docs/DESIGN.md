# ShipTrack Modern GCP — Design Document

| | |
|---|---|
| **Repository** | `shiptrack-modern-gcp` |
| **Author** | M.L. |
| **Status** | v0.2 |
| **Last updated** | 2026-10-16 |
| **Related** | `shiptrack-modern/docs/DESIGN.md`, `shiptrack-modern-azure/docs/DESIGN.md`, `shiptrack-platform/docs/DESIGN.md`, `shiptrack-legacy/docs/DESIGN.md` |

---

## 0. Instructions for the implementing agent

1. **Modern keeps running on AWS and Azure.** This repository adds a third, independent home for the same application on Google Kubernetes Engine. Nothing here changes how modern behaves on AWS or Azure. App changes live in `shiptrack-modern`, as separate pull requests that name what they implement (§5), and they leave AWS and Azure behavior and the frozen API contract alone.
2. **This repository holds no application code.** It holds GCP infrastructure (Terraform), GitHub workflows, GCP Helm values, CI checks, and docs.
3. **Cost is a design constraint** (ADR-0004). Choose the cheapest option that meets this design, record its approximate monthly cost in the ADR, and mark every price **[VERIFY]** until it is checked against Google's pricing pages.
4. **All infrastructure changes run through GitHub Actions** with GitHub OIDC and Workload Identity Federation, a separate service account per kind of job, and environment approval on every apply (ADR-0002). The implementing agent never runs `terraform apply`, `helm install/upgrade`, `kubectl apply`, or a `gcloud` command that creates, updates, or deletes a ShipTrack resource. It runs lint, format, validation, and read-only `gcloud` (`describe`, `list`, `get-iam-policy`), and it does not install `gcloud` components. It never reads or prints secret values, access tokens, or kubeconfig credentials unless asked.
5. **The organization's policies are in force.** Service account keys cannot be created or uploaded, buckets must use uniform access, and default service accounts get no automatic roles. Every choice below works with them. If something seems to need a key, stop and ask.
6. Pin all versions: Terraform providers and modules, Helm charts, base images by digest, GitHub Actions by full commit SHA.
7. Ask on ambiguity. Record decisions in `docs/ADR.md`. Items marked **[VERIFY]** must be checked against current documentation before use.
8. The repository is public. Follow the parent rules: no project ID or number, organization, folder, or billing account IDs, tag key or value IDs, service account emails, Workload Identity pool or provider names, bucket names, kubeconfig data, or cluster endpoint in any file, log, comment, artifact, or evidence. Use variables and placeholders such as `<PROJECT_ID>`. Values that a workflow needs live in GitHub secrets and are masked with `::add-mask::` before any step can print them.
9. **Say proof of delivery.** Every new GCP resource, setting, object prefix, and document spells out "proof of delivery" (`proof-of-delivery` when it qualifies a noun), never `pod` or `POD`. `pod` here means a Kubernetes pod only. Names that stored data or the shared code already depend on are kept (ADR-0023).

---

## 1. Goals and measurable targets

| Goal | Target |
|---|---|
| Same application, three clouds | The image running on GCP is the byte-identical digest that runs on AWS and Azure |
| Contract parity | The platform contract `full` suite passes against the GCP deployment (`TARGET=modern`) |
| Declarative delivery | Everything after the by-hand seed (§8.0) is created by a workflow after an approval; no manual `kubectl`, `helm`, or console steps |
| No stored credentials | No service account key anywhere; no secret in git, in Kubernetes Secrets, or on disk; values are read from Secret Manager at runtime (§12) |
| Zero-loss events | 0 lost events across a deploy and a Spot preemption, shown by the simulator ledger |
| Lowest cost | About $25 to $35 a month with no public address (§13), and cost per 1M requests at the same load profile **[VERIFY]** |
| Tagged | Every resource carries `environment: dev` and `name: shiptrack` (ADR-0003) |

**Non-goals** (each can become a later phase):
- Traffic shifting between AWS and GCP. GCP is its own environment with its own database (ADR-0019).
- Migrating data from RDS. The GCP database starts from the Alembic migrations.
- High availability: a regional cluster, a high-availability database, multiple zones.
- A public address by default (ADR-0013), KEDA (ADR-0012), and Grafana (ADR-0014).

---

## 2. Service mapping

| Concern | AWS (modern) | Azure | GCP |
|---|---|---|---|
| Orchestration | EKS | Existing AKS | GKE Autopilot, regional location `us-central1`, all workloads on Spot pods (ADR-0005) |
| Delivery | Helm from `deploy-app` with `--atomic` | Flux | Helm from `deploy-app` with `--atomic`, after approval (ADR-0015) |
| Image registry | ECR | GHCR | GHCR, the same public package and digest as Azure |
| Database | RDS PostgreSQL | Flexible Server | Cloud SQL for PostgreSQL, shared-core, private IP only (ADR-0008) |
| Secrets | Secrets Manager via Pod Identity | Key Vault | Secret Manager via Workload Identity Federation for GKE (ADR-0010) |
| Event queue | SQS with a DLQ | Service Bus queue | Pub/Sub topic and pull subscription with a dead-letter topic (ADR-0009) |
| Event bus | EventBridge bus, rule, archive | Service Bus topic with a filter | Pub/Sub topic with a filtered subscription and 7-day retention for replay |
| Proof-of-delivery storage | S3, presigned GET | Blob, SAS URL | Cloud Storage, V4 signed URL through the IAM signing API (ADR-0011) |
| Queue-based scaling | KEDA `aws-sqs-queue` | KEDA `azure-servicebus` | Fixed replica counts, no KEDA (ADR-0012) |
| Ingress | ALB with TargetGroupBinding | Gateway API | None by default; optional regional external Application Load Balancer through Gateway API (ADR-0013) |
| Metrics, logs | AMP, CloudWatch | In-cluster, to be decided | Managed Service for Prometheus, Cloud Logging, Cloud Monitoring (ADR-0014) |
| Terraform state | S3 | Blob | Cloud Storage bucket with native locking, created by the seed workflow (ADR-0016, ADR-0024) |
| Workload identity | IAM role per service account | Managed identity per service account | IAM principal per Kubernetes service account, no Google service account except the signer |
| CI to cloud | GitHub OIDC | None | GitHub OIDC with Workload Identity Federation, service account impersonation |

---

## 3. Architecture

```
 GitHub                                       GCP project (shiptrack), us-central1
 ──────                                      ──────────────────────────────────────────────────────
 shiptrack-modern ── release-image ──► GHCR (public) ── image by digest ──┐
   (app, chart)                                                           │
                                                                          ▼
 shiptrack-modern-gcp ── deploy-app (OIDC, approval) ─► helm --atomic ─► GKE Autopilot (private nodes)
   (this repo)         ▲                                       ┌──────────────────────────────────┐
                       │ DNS endpoint, IAM auth                │ namespace shiptrack (PSA restricted)│
                       └───────────────────────────────────────┤  api ×2 ──publish──► Pub/Sub topic  │
                                                               │   │   │             carrier-events   │
                                                               │   │   └ PUT / signed GET ► Cloud     │
                                                               │   │                       Storage    │
                                                               │   │      worker-events ◄─ subscription │
                                                               │   │        │      └─ publish ─► topic  │
                                                               │   ▼        │            shiptrack-events│
                                                               │ Cloud SQL ◄┘         subscription notify│
                                                               │ (private IP)            │              │
                                                               │ sla-scan (CronJob */5)  worker-notify  │
                                                               │ db-init · migrate (Jobs)          │
                                                               └──────────────┬───────────────────────┘
        egress to GHCR, GitHub, Google APIs via Cloud NAT                      │
        workload principals ──► Secret Manager (DB credentials)  ◄─────────────┘
```

Every pod authenticates with its own Kubernetes service account, which Google treats as an IAM principal. There are no Google service account keys and no Kubernetes Secrets. The api signs proof-of-delivery URLs by asking the IAM signing API to sign as a read-only signer service account.

---

## 4. Repository layout

```
shiptrack-modern-gcp/
├── docs/
│   ├── DESIGN.md  ADR.md
│   └── runbooks/                      # written after the build, not before
├── terraform/
│   ├── seed/                     # state bucket, APIs, service accounts, GitHub trust, permissions (README: one-time setup)
│   │   └── scripts/                   # ci.sh (plan/apply, first-run bucket seeding), github-setup.sh
│   ├── data/                          # network, NAT, Cloud SQL, Pub/Sub, bucket, Secret Manager, workload IAM, alerts
│   ├── cluster/                       # GKE Autopilot
│   ├── addons/                        # namespace, deployer RBAC, optional Gateway
│   └── modules/workload-access/       # one workload's IAM bindings
├── deploy/
│   ├── values-gcp.yaml                # non-identifying Helm values for cloud=gcp
│   ├── chart-ref                      # pinned shiptrack-modern commit SHA
│   └── db-init/                  # Job manifest and init.sql (schema, roles, grants)
├── scripts/                           # render checks, local helpers
├── .github/
│   ├── workflows/                     # apply-seed, ci-checks, ci-terraform, apply-terraform, destroy-*, deploy-app, ops-contract
│   ├── scripts/terraform-ci.sh        # plan/apply wrapper for data, cluster, and addons that masks identifiers
│   ├── scripts/terraform-destroy.sh   # shared by every destroy-* workflow (ADR-0027)
│   └── dependabot.yml                 # github-actions, terraform
├── .tflint.hcl  .checkov.yaml  .gitleaks.toml  .gitignore
└── README.md
```

**Four Terraform roots**, applied in this order: `seed`, `data`, `cluster`, `addons`. The `kubernetes` provider cannot be configured reliably from a cluster created in the same apply, so `addons` follows `cluster`. State objects: `gcp/<root>/default.tfstate` in the state bucket (ADR-0016).

---

## 5. Changes in `shiptrack-modern`

The application uses `boto3` in `secrets.py`, `storage/s3.py`, `events/publisher.py`, `events/worker.py`, and `logconfig.py`. The Azure design plans a `SHIPTRACK_CLOUD` setting that selects an implementation for each. GCP adds a third value, `gcp`, to the same seam. The seam is built once, as its own pull requests, with AWS as the default. These changes must land before the GCP deployment can run.

### 5.1 Cloud selection
`SHIPTRACK_CLOUD` is `aws` (default), `azure`, or `gcp`. The interfaces stay: a secret source, an event publisher, an event consumer, a notification publisher, an object store. Settings are validated per cloud; unset GCP variables are an error only when `SHIPTRACK_CLOUD=gcp`.

### 5.2 GCP settings

| Variable | Used by | Notes |
|---|---|---|
| `SHIPTRACK_GCP_PROJECT` | all | The project ID. Supplied at deploy time from a masked secret, never in a values file |
| `SHIPTRACK_DB_SECRET_NAME` | all except migrate | Secret with the same JSON shape as the AWS secret (`host`, `port`, `dbname`, `username`, `password`). A short name; the project comes from the setting above |
| `SHIPTRACK_DB_MIGRATOR_SECRET_NAME` | migrate | |
| `SHIPTRACK_EVENTS_TOPIC` | api | Topic the api publishes to |
| `SHIPTRACK_EVENTS_SUBSCRIPTION` | worker-events | Pull subscription on that topic |
| `SHIPTRACK_NOTIFY_TOPIC` | worker-events | Topic worker-events publishes `ShipmentDelivered` and `ShipmentException` to |
| `SHIPTRACK_NOTIFY_SUBSCRIPTION` | worker-notify | Filtered subscription on the notification topic |
| `SHIPTRACK_PROOF_OF_DELIVERY_BUCKET` | api | The proof-of-delivery bucket name. A new setting that spells the document out (ADR-0023); AWS keeps `SHIPTRACK_POD_BUCKET`, as modern ADR-0030 requires |
| `SHIPTRACK_PROOF_OF_DELIVERY_SIGNER` | api | Email of the read-only service account `shiptrack-proof-of-delivery`, which signs download URLs. Supplied at deploy time from a masked secret |

Credentials come from Application Default Credentials, which on GKE resolve through Workload Identity Federation. No variable names a key file.

### 5.3 Behavior differences the code must handle

| Area | AWS | GCP |
|---|---|---|
| Send | `SendMessage`; 503 `QUEUE_UNAVAILABLE` on failure | `publish` and wait for the result; 503 `QUEUE_UNAVAILABLE` on failure, so 202 still means durably queued |
| Receive | Long poll 20 s, batch 10 | Synchronous `pull`, up to 10 messages **[VERIFY return behavior with no messages]** |
| In-flight time | Visibility timeout 60 s, `ChangeMessageVisibility` | Ack deadline 60 s, `modify_ack_deadline` to extend |
| Acknowledge | `DeleteMessage` per message | `acknowledge` per message; `modify_ack_deadline(0)` on failure |
| Dead-lettering | `maxReceiveCount` 5 to a DLQ | `max_delivery_attempts` 5 to a dead-letter topic with its own pull subscription for inspection |
| Idempotency | `idempotency_key` message attribute | The same attribute. Pub/Sub delivers at least once; the worker already applies `INSERT … ON CONFLICT (idempotency_key) DO NOTHING` |
| Notification routing | EventBridge rule on `detail-type` | Subscription filter on the message attribute `detail_type`, which the publisher sets |
| Replay | EventBridge archive, 7 days | Topic message retention of 7 days and `seek`, which keeps the archive that Azure lacks |
| Proof-of-delivery upload | `upload_fileobj` to the key `pod/{shipment_id}/{document_id}`, stored as an `s3://` URI | `upload_from_file` streamed, sha256 computed while streaming, to the object `proof-of-delivery/{shipment_id}/{document_id}`, stored as a `gs://` URI. The `pod_documents` table is shared schema and keeps its name (ADR-0023) |
| Proof-of-delivery download | `302` to a presigned GET, TTL 300 s | `302` to a V4 signed URL, TTL 300 s, signed through the IAM signing API as the proof-of-delivery signer service account |
| Secret rotation | Refetch once after an authentication failure | The same, using the existing cache invalidation |
| Logs | JSON on stdout | The same JSON, plus `severity` and `message` fields so Cloud Logging reads the level and text. Other fields are unchanged |
| Spot preemption | Not applicable | The pod gets SIGTERM with a short grace period. In-flight messages are redelivered, and the worker is idempotent, so nothing is lost |

The credential shape, the redaction filter, the `DbCredentials` type, and all metrics and log fields are unchanged. The API contract and the UI are unchanged.

### 5.4 Dependencies and image size
`google-cloud-secret-manager`, `google-cloud-pubsub`, `google-cloud-storage`, and `google-auth` join the one image, because the same digest must run on every cloud. The image-size target in modern §6 is re-measured and, if exceeded, recorded in modern's ADR. The Azure dependencies are added by the Azure work; the two sets are independent.

### 5.5 Tests
Unit tests use fakes for each Google client. Integration tests in the local compose file use:
- **The Pub/Sub emulator** for topics, subscriptions, filters, and dead-lettering. Whether it supports filters and dead-letter policies as the design uses them is checked when the tests are written **[VERIFY]**; any behavior it lacks is covered by fakes.
- **A fake Cloud Storage server** (an open-source emulator) for upload and download. The signing path is tested against a fake IAM client.
- **No Secret Manager emulator** is assumed. The secret source is tested against a fake client.

The contract suite is the cross-cloud check (§9.3).

### 5.6 Chart switches
The chart gains the `cloud` value that the Azure work adds, with `gcp` as a third setting. For `gcp` it:
- does not render the `TargetGroupBinding` or any KEDA object;
- renders workers with fixed replica counts (`scaling.mode: fixed`, ADR-0012) and no HPA;
- selects Spot capacity with the `cloud.google.com/gke-spot: "true"` node selector;
- uses the GCP block of settings in place of the `aws` block;
- renders the NetworkPolicies with namespace and pod selectors; the optional Gateway needs Google's health-check and proxy ranges as `ipBlock` rules;
- renders a `PodMonitoring` resource for port 9090 at a 60-second interval (ADR-0014).

The schema (`values.schema.json`) requires the right set per cloud. The `aws` render stays byte-identical, checked in modern's CI.

### 5.7 Release workflow
`release-image.yml` also publishes the merged image to GHCR, as the Azure design requires (Azure design §6). That pull request serves both clouds. GCP adds no registry.

---

## 6. Container image

- The image is the one `release-image` publishes to GHCR as a public package, deployed by digest only. Tags are for people.
- GKE pulls through Cloud NAT. No image pull secret exists.
- The index carries both architectures. Autopilot's default is amd64. Running on Arm may cost less; it is a values change, tested after the first deploy **[VERIFY the Autopilot Arm compute class and price]**.

---

## 7. Kubernetes and Helm

### 7.1 Namespace
`shiptrack`, created by `terraform/addons` with `pod-security.kubernetes.io/enforce: restricted` and `warn: restricted`. The AWS readiness-gate label is not used.

### 7.2 Workloads
All workloads use Spot pods (ADR-0005). The totals drive the cost in §13.

| Workload | Kind | Replicas | Requests | Memory limit |
|---|---|---|---|---|
| api | Deployment | 2, `maxUnavailable: 0`, no HPA | 250m, 256Mi | 512Mi |
| worker-events | Deployment | 1 | 100m, 256Mi | 512Mi |
| worker-notify | Deployment | 1 | 50m, 128Mi | 256Mi |
| sla-scan | CronJob `*/5 * * * *`, `concurrencyPolicy: Forbid`, active | — | 100m, 128Mi | 256Mi |
| migrate | Job (Helm hook), enabled, because this environment owns its schema (ADR-0019) | — | 100m, 128Mi | 256Mi |
| db-init | Job run by `deploy-app` before the release (§8.1) | — | 100m, 128Mi | 256Mi |

Autopilot bills requests and rounds them up to its own minimums and ratios **[VERIFY the rounding for the smallest pods]**. There are no CPU limits, as in modern §7.2. The pod security context, probes, topology spread, PDBs, and `emptyDir` `/tmp` are those of modern §7.2. The two api replicas keep the zero-downtime termination settings (REM-12) without the load balancer parts.

**Spot preemption.** GKE gives a Spot node a short shutdown window, shorter than the 90 seconds worker-events asks for. A cut-off message is redelivered and applied once. Both api replicas can be preempted together, which is a short outage and an accepted risk (G-R2).

### 7.3 Identity

| Kubernetes service account | Access (IAM principal) |
|---|---|
| `shiptrack-api` | `pubsub.publisher` on the events topic; `secretmanager.secretAccessor` on the app secret; `storage.objectUser` on the proof-of-delivery bucket; `iam.serviceAccountTokenCreator` on `shiptrack-proof-of-delivery` |
| `shiptrack-worker-events` | `pubsub.subscriber` on the events subscription; `pubsub.publisher` on the notification topic; `secretmanager.secretAccessor` on the app secret |
| `shiptrack-worker-notify` | `pubsub.subscriber` on the notification subscription |
| `shiptrack-sla-scan` | `secretmanager.secretAccessor` on the app secret |
| `shiptrack-migrate` | `secretmanager.secretAccessor` on the migrator secret |
| `shiptrack-db-init` | `secretmanager.secretAccessor` on the admin secret |

Each binding is on the single resource, never on the project. The principal is the Kubernetes service account named in the namespace `shiptrack`. The signer service account has `storage.objectViewer` on the bucket and nothing else, so a signed URL can only read.

### 7.4 Network
- Nodes are private and reach GHCR, GitHub, and Google APIs through Cloud NAT (ADR-0007).
- Default deny ingress in the namespace. Port 9090 is admitted from the managed Prometheus collectors by namespace selector.
- With no Gateway, nothing outside the cluster can reach the api. Operators and the contract run reach it with `kubectl port-forward` through the cluster's DNS endpoint (ADR-0013).
- Egress is unrestricted (documented).

### 7.5 Values
`deploy/values-gcp.yaml` holds replica, resource, and Spot settings. Identifying values (project, signer email, secret names that embed an identifier) are passed with `--set` from masked secrets. The chart's schema requires `image.digest` (`^sha256:[a-f0-9]{64}$`).

---

## 8. Infrastructure (Terraform)

Provider `google`, pinned to an exact version, and Terraform 1.11 or later for write-only arguments **[VERIFY the provider major and the minimum version for each write-only argument]**. The backend is `gcs`. The seed workflow creates the state bucket and writes a gitignored `backend.tf` that names it, so no committed file does (ADR-0016). The project is `TF_VAR_project_id`, from a masked secret. Every resource that takes labels gets `environment = "dev"` and `name = "shiptrack"` from one `local.labels` map, or from provider-level default labels if the pinned provider supports them **[VERIFY]**.

### 8.0 Seed by hand
The user creates these once, because the first run needs them to exist. The commands are in `terraform/seed/README.md`.
1. The repository `shiptrack-modern-gcp` with `dev` as its default branch, and its numeric ID and its owner's numeric ID. The repository must issue OIDC tokens with the immutable subject `repo:<owner>@<owner id>/<repo>@<repo id>`, which the README checks.
2. The five APIs the federation needs: IAM, IAM Credentials, Security Token Service, Resource Manager, and Service Usage.
3. A Workload Identity pool and an OIDC provider for `https://token.actions.githubusercontent.com`. The subject is the token's `sub` claim. The attribute condition matches the numeric repository ID and the numeric owner ID, so a renamed or transferred repository, or any other repository, cannot authenticate.
4. The seed service account `shiptrack-seed`, with the roles the seed root needs, and one trust binding: only the subject `…:environment:seed` can impersonate it.
5. The GitHub environments `seed`, `ci`, and `dev` (the user as required reviewer on each; `seed` and `dev` admit only the `dev` branch, `ci` admits pull request runs), branch protection, and the secrets the workflows read, from `terraform/seed/scripts/github-setup.sh` and the README.

The state bucket, the other service accounts, their trust, and their permissions are not by hand: the workflow creates them (§8.1).

### 8.1 `terraform/seed`
Applied by the `apply-seed` workflow as the seed service account. Both its jobs run in the `seed` environment: the user approves the first to read the plan summary, which lists addresses and actions only, then approves the second to apply. On the first run `scripts/ci.sh` creates only the state bucket with local state, writes `backend.tf`, and migrates the state into the bucket before creating anything else (ADR-0024).

| Resource | Notes |
|---|---|
| State bucket | `shiptrack-tfstate-<project number>` in `us-central1`: uniform access, public access prevention enforced, versioning on, the newest ten versions kept, labeled, `prevent_destroy` |
| Project services | Every API the other roots need: compute, container, sqladmin, servicenetworking, pubsub, secretmanager, storage, monitoring, logging, and the five from §8.0 |
| Service accounts | `shiptrack-plan`, `shiptrack-apply`, `shiptrack-deploy`, `shiptrack-gke-node`, and `shiptrack-proof-of-delivery`. All are created here, so no later account needs to create service accounts |
| Trust | One `workloadIdentityUser` binding per exact subject. `plan`: `…:environment:ci`. `apply` and `deploy`: `…:environment:dev`. Every subject names an environment that needs the user's approval (ADR-0025). A job outside the approved environment cannot become `plan`, `apply`, or `deploy` |
| Plan roles | `viewer`, `iam.securityReviewer`, `serviceusage.serviceUsageConsumer`, and `storage.objectViewer` on the state bucket. Plans run with `-lock=false`, so they never write state |
| Apply roles | Admin roles for Cloud SQL, networking, GKE, logging configuration, monitoring, Pub/Sub, Secret Manager, Service Networking, and Cloud Storage; `serviceusage.serviceUsageConsumer`; `storage.objectUser` on the state bucket; `serviceAccountUser` on `shiptrack-gke-node`; `serviceAccountAdmin` on `shiptrack-proof-of-delivery` only. No project-level IAM admin and no service account admin on the project (ADR-0022) |
| Deploy roles | `container.clusterViewer` to fetch credentials through the DNS endpoint, and `serviceusage.serviceUsageConsumer`. All cluster permissions are Kubernetes RBAC in one namespace (§8.4) |
| Node role | `container.defaultNodeServiceAccount` for `shiptrack-gke-node` |

The workflow reads these from GitHub: secrets `GCP_PROJECT_ID`, `GCP_PROJECT_NUMBER`, `GCP_WORKLOAD_IDENTITY_PROVIDER`, and `GCP_SEED_SERVICE_ACCOUNT` (in the `seed` environment), and the variable `GCP_REGION`. The owner and repository names and IDs come from the workflow context.

### 8.2 `terraform/data`

| Resource | Notes |
|---|---|
| VPC | Custom mode, one subnet in `us-central1` with secondary ranges for pods and services sized for one or two nodes, Private Google Access on, flow logs off (cost) |
| Cloud NAT and router | One gateway, automatic IP allocation, logging errors only |
| Private services access | An allocated range and peering for Cloud SQL |
| Cloud SQL | PostgreSQL 17, `edition = ENTERPRISE` set explicitly, tier `db-f1-micro`, zonal, 10 GiB, private IP only, `ssl_mode = ENCRYPTED_ONLY`, daily backups kept 7 days, point-in-time recovery off, deletion protection on, database `shiptrack` (ADR-0008). The administrator password uses a write-only argument **[VERIFY]** |
| Pub/Sub | Topic `shiptrack-carrier-events` with a pull subscription (ack deadline 60 s, retention 4 d, dead-letter after 5 attempts) and a dead-letter topic with a pull subscription (retention 14 d). Topic `shiptrack-notifications` (retention 7 d) with a subscription filtered on `detail_type`, with the same dead-letter setup. The Pub/Sub service agent gets publisher on each dead-letter topic and subscriber on each source subscription |
| Cloud Storage | One bucket named `shiptrack-proof-of-delivery-<random suffix>` in `us-central1`, Standard class, uniform access, public access prevention enforced, versioning off, soft delete at the default. Objects live under `proof-of-delivery/` (ADR-0023) |
| Secret Manager | Secrets for the app, migrator, and admin credentials. Values are written with a write-only argument from an ephemeral random password, so they are not in state |
| Proof-of-delivery signer | The account `shiptrack-proof-of-delivery` is created by the seed root; this root gives it `storage.objectViewer` on the bucket and lets the api principal create tokens for it |
| Workload bindings | One `modules/workload-access` call per row of §7.3 |
| Alerts and dashboard | §11 |

**Naming:** `shiptrack-` prefix for resources; globally unique names (bucket) add a `random_string` suffix. No identifier is hardcoded.

**db-init:** `deploy/db-init/init.sql` creates the schema, the `shiptrack_app` and `shiptrack_migrator` roles, and their grants, as the Azure variant does. `deploy-app` runs it as a Job before the release, with the admin secret, and it is idempotent.

### 8.3 `terraform/cluster`
GKE Autopilot cluster `shiptrack` in `us-central1`: release channel `REGULAR`, private nodes, the DNS-based control-plane endpoint on and the IP-based endpoint off, no authorized networks to maintain, Workload Identity on (Autopilot default), system and workload logging, managed Prometheus collection, `deletion_protection = true`, and the labels above **[VERIFY the Terraform arguments for the DNS endpoint]**.

### 8.4 `terraform/addons`
Providers: `kubernetes`, authenticated with the apply account's short-lived token through the DNS endpoint.
- Namespace `shiptrack` with the labels of §7.1.
- A `Role` and `RoleBinding` that give the `shiptrack-deploy` account the workload kinds, `Job`/`CronJob`, `NetworkPolicy`, `PodMonitoring`, `pods/portforward`, and Secrets (Helm release storage) in that namespace only.
- The `Gateway` and its policies, only when `gateway_enabled` is true (ADR-0013).

### 8.5 Applying
`apply-terraform` runs the roots in order, each after its own approval. The agent prepares the code and runs `fmt`, `validate`, `tflint`, and `checkov`. Before each approval, the agent states what the pull request's plan will create, change, or destroy.

---

## 9. Delivery

### 9.1 Release flow
1. A merge to `dev` in `shiptrack-modern` runs `release-image`, which publishes the digest to ECR and GHCR.
2. `deploy-app` is started by hand with that digest. It cannot follow `release-image` by `workflow_run`, because the two are in different repositories.
3. After the approval it deploys. A failed release rolls back, and the job fails.

### 9.2 Workflows

| Workflow | Trigger | Does |
|---|---|---|
| `ci-checks` | pull request | Static checks (§10), in environment `ci` |
| `ci-terraform` | pull request | In environment `ci`, `plan` for `data`, `cluster`, and `addons` as `shiptrack-plan`, with `-lock=false`; comment shows addresses and actions only; no plan artifacts. `seed` is planned only by `apply-seed`, because the first run precedes the plan account |
| `apply-seed` | dispatch | Applies `terraform/seed` as the seed account: two jobs in the `seed` environment, plan then apply, each approved (§8.1) |
| `apply-terraform` | dispatch | `apply` in the order `data`, `cluster`, `addons` as `shiptrack-apply`, in the `dev` environment with approval |
| `destroy-*` | dispatch with a confirmation | Takes down one cost-bearing resource group (§9.4) |
| `deploy-app` | dispatch with a digest | Deploy (below) |
| `ops-contract` | dispatch | Contract suite through a port-forward (§9.3) |

`deploy-app`:
1. `environment: dev` (the user approves); `concurrency: deploy-dev` without cancel.
2. Authenticate as `shiptrack-deploy`; fetch credentials through the DNS endpoint on the runner only.
3. Check out `shiptrack-modern` at the commit in `deploy/chart-ref` for the chart.
4. Run the `db-init` Job and wait for it.
5. `helm upgrade --install shiptrack … -f deploy/values-gcp.yaml --set image.digest=$DIGEST --atomic --wait --timeout 10m --history-max 10`, with identifying values from masked secrets.
6. While it waits, a read-only sampler prints pods, events, and the logs of any not-Ready pod every 30 seconds, masked, because `--atomic` removes them on failure.
7. `kubectl rollout status` for each Deployment, then the contract `smoke` suite through a port-forward.

### 9.3 Validation
The platform contract suite reads `BASE_URL`, `TARGET`, `TEST_TOKEN`, and `SINGLE_STACK`. The routing headers steer the AWS load balancer, so the GCP run uses:
- `BASE_URL` = `http://localhost:<port>`, a port-forward to the api service;
- `TARGET=modern`, so the stack header is still asserted;
- `TEST_TOKEN` empty, and the AWS token is never sent to GCP;
- `SINGLE_STACK=1`.

The suite needs no change. `ops-contract` runs it from a GitHub-hosted runner with no inbound path to the cluster (ADR-0020).

### 9.4 Destroy workflows
Every pull request that provisions a cost-bearing resource also adds its destroy workflow (ADR-0027). They stop spend one group at a time:

| Workflow | Takes down |
|---|---|
| `destroy-addons` | Namespace, deploy RBAC, Gateway |
| `destroy-cluster` | GKE Autopilot cluster |
| `destroy-cloud-sql` | Cloud SQL instance, database, users |
| `destroy-network` | VPC, subnet, router, Cloud NAT, private services access |
| `destroy-pubsub` | Topics, subscriptions, dead-letter topics |
| `destroy-proof-of-delivery-storage` | The proof-of-delivery bucket |
| `destroy-secrets` | Secret Manager secrets |
| `destroy-monitoring` | Alert policies, notification channel, dashboard |

Each runs as `shiptrack-apply` in the `dev` environment with two approvals, plan then destroy. The plan lists addresses and actions only, and fails unless the `confirm` input equals the resource name. The protections (`deletion_protection`, `force_destroy`) are lowered inside the approved run and are on again for anything that remains. Remove groups in reverse order: addons, cluster, then Cloud SQL before the network. The seed root has no destroy workflow.

---

## 10. CI

`ci-checks.yml`, on pull requests, all jobs required. Every job runs in environment `ci`, so the user approves each run before any job starts (ADR-0025):

| Job | Steps |
|---|---|
| `terraform` | Per root: `terraform fmt -check`, `init -backend=false`, `validate`, `tflint`; `checkov`; `trivy config` |
| `chart` | Check out `shiptrack-modern` at the pinned commit; `helm lint`; `helm template` with `values-gcp.yaml` and a dummy digest; `kubeconform -strict`; `checkov` on the render |
| `secrets` | `gitleaks`, with custom rules for project numbers, service account emails, and Workload Identity resource names, plus a scrub of any standalone 12-digit number, which is the shape of a project number. Generated lock files, whose hashes contain digit runs, are allowlisted, as in `shiptrack-platform` |
| `workflows` | `actionlint`; all actions pinned to SHAs; every job in every workflow names an `environment:` |

`ci-checks` and `ci-terraform` use no credentials except the plan account's read-only token, and only in `ci-terraform`.

---

## 11. Observability and reliability

- The application exposes the same Prometheus metrics on port 9090 and the same JSON logs on stdout.
- **Metrics:** Managed Service for Prometheus collects port 9090 through a `PodMonitoring` resource at a 60-second interval. Queries and alerts use PromQL in Cloud Monitoring. There is no Grafana (ADR-0014).
- **Logs:** Cloud Logging ingests stdout. Health-check access logs are dropped by the app. Ingestion should stay inside the monthly free allotment **[VERIFY]**.
- **Alerts** (Cloud Monitoring policies from Terraform, one notification channel whose address is a masked secret):

| Alert | Condition | Sev |
|---|---|---|
| events-queue-age | oldest unacked message on the events subscription > 120 s for 5 min | SEV2 |
| events-queue-age-critical | > 600 s for 5 min | SEV1 |
| events-dlq-visible | undelivered messages on the events dead-letter subscription > 0 | SEV2 |
| notify-dlq-visible | the same for notifications | SEV2 |
| pod-restarts | container restarts in the `shiptrack` namespace above 3 in 10 min | SEV2 |
| sla-scan-heartbeat | a log-based metric on `sla_scan_completed` absent for 15 min | SEV2 |
| availability-fast-burn | 5xx ratio burn over 1 h and 5 min, PromQL **[VERIFY PromQL alert policies]** | SEV1 |

- **Dashboard:** one Cloud Monitoring dashboard from Terraform: request rate, errors, latency, subscription depth and age, pod restarts, database connections.
- SLO targets are those of modern §11.1; the latency and freshness SLOs are read from the histograms.

---

## 12. Security

- **Checklist**, from modern §12 where it applies:
  - [ ] PSA `restricted` enforced
  - [ ] Every pod non-root with a read-only root filesystem and all capabilities dropped
  - [ ] One IAM principal per workload, each binding on a single resource
  - [ ] No Kubernetes Secrets holding credentials
  - [ ] Images deployed by digest
  - [ ] Trivy, Checkov, gitleaks, kubeconform gating
  - [ ] REM-16 headers on every response
- **No keys anywhere.** The organization forbids service account keys. CI authenticates with a one-hour token from GitHub OIDC. Workloads use Workload Identity Federation. Signed URLs use the IAM signing API.
- **Federation is pinned to this repository** by numeric IDs and, for `apply` and `deploy`, to the approved environment's subject. A pull request cannot become `apply`.
- **No public addresses.** Nodes are private, the database has a private IP only, the control plane is reached through an IAM-authenticated DNS endpoint, and there is no load balancer unless enabled (ADR-0013).
- **Data:** the database requires TLS; the bucket enforces uniform access and public access prevention; secrets are in Secret Manager and out of Terraform state.
- **No path to escalate:** the apply account holds no project-level IAM admin and no service account admin on the project. Service accounts are created once by the seed root, and grants on a resource come from that service's own admin role (ADR-0022).
- **State** holds no secret values. The bucket is reachable only by the three accounts.
- **Audit:** Admin Activity logs are on and free. Data Access logs stay off except for Secret Manager **[VERIFY the cost]**.

---

## 13. Cost

All figures are approximate monthly costs in `us-central1`, **[VERIFY against Google's pricing pages before quoting]**. The ADRs hold the reasoning and the alternatives.

| Item | Basis | Per month |
|---|---|---|
| GKE management fee | $0.10 per cluster-hour, covered by the $74.40 monthly credit for one Autopilot or zonal cluster per billing account. This project is the only one on its billing account | $0 |
| Autopilot Spot pods | About 0.65 vCPU and 0.9 GiB requested. On demand this is about $24 ($0.0445 per vCPU-hour, $0.0049 per GiB-hour). Spot is 60% to 91% off | $5 to $10 |
| Cloud NAT | $0.0014 per VM-hour for one or two nodes, plus about $0.005 per hour for the gateway's address, plus $0.045 per GiB | $4 to $6 |
| Cloud SQL `db-f1-micro` | Shared-core, zonal, 10 GiB, 7-day backups | $10 to $13 |
| Pub/Sub | First 10 GiB a month free | ≈ $0 |
| Secret Manager | Six active versions and 10,000 accesses free | ≈ $0 |
| Cloud Storage | 5 GiB free in `us-central1` | ≈ $0 |
| Logging and Monitoring | Logging within the free allotment; Managed Prometheus samples; a few alert conditions | $2 to $5 |
| State bucket | A few small objects | ≈ $0 |
| **Baseline total** | | **about $25 to $35** |
| Optional regional external load balancer | One forwarding rule at $0.025 per hour | + about $18 |
| Optional Cloud Armor allow-list | One policy and rule | + about $6 |

`docs/cost/analysis.md` records the real monthly cost from the billing export, grouped by label, and cost per 1M requests at the load profile used for AWS. It reports honestly if GCP costs more at this scale.

Cheaper options considered and rejected: a Standard zonal cluster with one Spot node (ADR-0005), Postgres inside the cluster (ADR-0008), public node addresses instead of NAT (ADR-0007).

---

## 14. Risks

| ID | Risk | Mitigation |
|---|---|---|
| G-R1 | Cost estimates rest on third-party and remembered prices | Every figure is marked [VERIFY]; the billing export is the source of record |
| G-R2 | Spot preemption can take both api replicas at once | Dev environment; two replicas spread by host; PDB; idempotent workers; switch `spot: false` if it hurts |
| G-R3 | Shared-core Cloud SQL has no SLA, little memory, and a low connection limit | Connection budget (ADR-0018); upgrade the tier if measured need exceeds it |
| G-R4 | Zonal database: a zone outage is an outage | Accepted for dev; backups for recovery |
| G-R5 | The apply account is powerful: its admin roles cover the cluster (cluster-admin), the network, and every bucket in the project, including the state bucket | Reachable only from the approved environment; no project IAM or service account administration (ADR-0022); state versioning allows recovery |
| G-R15 | `apply` and `deploy` trust the same subject (`environment:dev`), so any job in that environment can request either | The environment admits only the reviewed `dev` branch, and workflows reach it through a pull request; the same trade as the AWS repositories |
| G-R16 | The seed account holds powerful roles | Reachable only from the `seed` environment; not managed by Terraform; narrowed or deleted once the seed root is stable |
| G-R6 | GitHub environment approval is the only gate | The user is the sole reviewer; protected `dev` branch |
| G-R7 | A renamed or transferred repository could match the federation condition | The condition uses numeric IDs |
| G-R8 | The control plane is reachable from any network with IAM credentials | IAM is the gate; no IP allow-list to leak; accepted |
| G-R9 | Pub/Sub delivers at least once | The worker is idempotent on the idempotency key |
| G-R10 | Cloud NAT is a fixed cost with no traffic | Smallest configuration; removable only by making nodes public, which is rejected |
| G-R11 | Public repository and cloud identifiers | Scrub and gitleaks rules (§10); masked secrets |
| G-R12 | The cloud seam is shared with Azure and not yet built | Built once in `shiptrack-modern`, with tests for all clouds |
| G-R13 | The free-tier credit covers one cluster per billing account | This project is the only one on the billing account; a second cluster there would cost about $73 a month |
| G-R14 | Autopilot rounds requests up, which can raise the bill | Measured after the first deploy; sizes adjusted |

---

## 15. Acceptance criteria

1. Modern's `release-image` publishes one digest to ECR and GHCR; GCP runs that digest.
2. `shiptrack-modern` runs with `SHIPTRACK_CLOUD=gcp` against GCP resources, and with `aws` and `azure` against theirs, with AWS and Azure behavior unchanged.
3. Every GCP resource except the by-hand seed (§8.0) is created by Terraform that a workflow applied after approval.
4. No service account key exists. No Kubernetes Secret holds a credential. No credential or identifier is in git. The secret scan passes.
5. The platform contract `full` suite passes through a port-forward.
6. The simulator ledger shows zero lost events across a deploy and a Spot preemption.
7. Exactly one `sla_alerts` row per breached shipment.
8. `/ui/` is served with the REM-16 headers and the stack badge reads `modern`.
9. Every resource carries `environment: dev` and `name: shiptrack`; the project carries both tags.
10. The baseline monthly cost is within the range in §13, or the difference is explained in `docs/cost/analysis.md`.
11. The runbooks (deploy and rollback, dead-letter redrive, secret rotation, state recovery) exist and are tested once.
12. Every cost-bearing resource group has a destroy workflow (§9.4), and each was run once against its group.

---

## 16. Implementation phases

Phases are applied in order; a phase's "Done when" must pass before the next starts. Terraform phases are applied by workflow after approval. A phase that provisions a cost-bearing resource also delivers that resource's destroy workflow (§9.4), and the phase is not done without it.

| Phase | Deliverables | Done when |
|---|---|---|
| **G0 Design** | This document; `docs/ADR.md`; the GCP section of the parent working rules | Reviewed by the user |
| **G1 App seam** (`shiptrack-modern`) | `SHIPTRACK_CLOUD` with `gcp`; secret source, publisher, consumer, object store; settings and tests. Shared with the Azure work | `pytest` green for every cloud; AWS behavior unchanged |
| **G2 Chart switches** (`shiptrack-modern`) | `cloud: gcp`, fixed scaling, Spot selector, `PodMonitoring`, per-cloud schema | AWS render identical; GCP render passes `kubeconform` |
| **G3 Image** (`shiptrack-modern`) | GHCR publish with digest equality check (shared with Azure) | The same digest is in both registries; package public |
| **G4 Seed** | The by-hand steps (§8.0); `terraform/seed`; the `apply-seed` workflow | `apply-seed` has run twice: the second run ends with "No changes"; the five accounts, the state bucket, and the trust exist |
| **G5 Data root** | Network, NAT, Cloud SQL, Pub/Sub, bucket, secrets, workload IAM | Applied by workflow; outputs defined; no value printed |
| **G6 Cluster root** | GKE Autopilot | Cluster reachable through the DNS endpoint by `deploy` |
| **G7 Addons root** | Namespace, deployer RBAC | Deploy account can list pods in the namespace and nothing outside it |
| **G8 Workflows** | `ci-checks`, `ci-terraform`, `apply-terraform`, `deploy-app`, `ops-contract` | `actionlint` passes; all actions SHA-pinned |
| **G9 Application** | `db-init`, `migrate`, the release | Release ready; `/readyz` 200 |
| **G10 Validation** | Contract suite, ledger, SLA check, preemption test | Acceptance criteria 5 to 8 |
| **G11 Operations** | Alerts, dashboard, runbooks, cost analysis | Runbooks tested once |

---

## 17. Verify-at-build-time list

Checked against current documentation:
- [x] The GKE management fee is $0.10 per cluster-hour, and the $74.40 monthly credit per billing account covers one Autopilot or zonal cluster, not regional ones
- [x] Cloud NAT is $0.0014 per VM-hour up to 32 VMs, plus $0.045 per GiB
- [x] KEDA supports `podIdentity.provider: gcp` and a Pub/Sub scaler (not used, ADR-0012)
- [x] Organization policies forbid service account key creation and upload (read from the organization)
- [x] `shiptrack-modern-gcp` issues OIDC tokens with the immutable subject prefix `repo:<owner>@<owner id>/<repo>@<repo id>` (`gh api repos/<owner>/<repo>/actions/oidc/customization/sub`)
- [x] The Google-provider major is 8 (8.7.0 at the time of writing) and `terraform validate` passes against it; the 19 predefined roles in `permissions.tf` exist

Still to confirm at build time:
- [ ] Autopilot per-vCPU and per-GiB prices in `us-central1`, Spot prices, minimum request sizes, and rounding (the official pricing page did not load; third-party figures are used)
- [ ] The Autopilot Arm compute class and whether it is cheaper
- [ ] Cloud SQL `db-f1-micro` price and the default `max_connections` for PostgreSQL (`SHOW max_connections` after the first apply)
- [ ] `edition = ENTERPRISE` must be set explicitly in Terraform
- [ ] Write-only arguments: `password_wo` on the Cloud SQL user and the Secret Manager secret version, and their minimum provider versions
- [ ] The GKE DNS-based control-plane endpoint: the Terraform arguments and the IAM permission needed
- [ ] The Workload Identity provider's claim names and attribute condition with numeric repository and owner IDs
- [ ] The IAM condition that limits which roles `projectIamAdmin` can grant
- [ ] Signing a V4 URL through the IAM signing API from a pod with no Google service account, and the roles it needs
- [ ] That the `:environment:` subject suffix is unchanged from the default format, as on the AWS repositories (the first run of `apply-seed` shows it; a mismatch appears as a failed authentication)
- [ ] `gcloud storage buckets describe` on a missing bucket reports 404 from the runner, with the credentials the auth action writes (the first run of `apply-seed`)
- [ ] The roles the `gcs` backend needs on the state bucket (`storage.objectUser` for apply, `storage.objectViewer` with `-lock=false` for plan)
- [ ] `roles/container.defaultNodeServiceAccount` is sufficient for Autopilot nodes, and `roles/container.clusterViewer` carries the permission to connect through the DNS endpoint
- [ ] The Pub/Sub emulator's support for filters and dead-letter policies
- [ ] Synchronous `pull` behavior with no messages
- [ ] Spot node shutdown grace on Autopilot and its effect on `terminationGracePeriodSeconds`
- [ ] Whether provider-level default labels exist in the pinned provider
- [ ] Managed Prometheus sample price, PromQL alert policies, alert condition price, and the Logging and Secret Manager free allotments
- [ ] Whether inherited tags appear in the billing export, or only labels do
- [ ] Regional external Application Load Balancer forwarding-rule price and Cloud Armor price (ADR-0013)
- [ ] That `crane copy` yields an identical index digest on GHCR (the workflow asserts it)
