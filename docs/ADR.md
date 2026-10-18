# ShipTrack Modern GCP — Architecture Decision Log

Decisions are recorded here, oldest first. Each entry has a status (Planned, Accepted, Superseded) and, once decided, Context, Decision, and Consequences. Accepted entries follow the user's instructions or the parent working rules. Entries marked Planned are recommendations that wait for the user's confirmation or for a **[VERIFY]** result, and the design is written to match them. Prices are approximate monthly costs in `us-central1` and are **[VERIFY]** until checked against Google's pricing pages.

| # | Title | Status |
|---|---|---|
| 0001 | `one-app-three-clouds` | Accepted |
| 0002 | `github-oidc-and-workload-identity-federation` | Accepted |
| 0003 | `tags-and-labels` | Accepted |
| 0004 | `cost-is-a-design-constraint` | Accepted |
| 0005 | `gke-autopilot-with-spot-pods` | Accepted |
| 0006 | `region-us-central1` | Accepted |
| 0007 | `private-nodes-and-cloud-nat` | Accepted |
| 0008 | `cloud-sql-shared-core-private-ip` | Accepted |
| 0009 | `pubsub-for-queues-and-notifications` | Accepted |
| 0010 | `secret-manager-and-workload-identity` | Accepted |
| 0011 | `cloud-storage-and-signed-urls` | Accepted |
| 0012 | `fixed-replicas-without-keda` | Accepted |
| 0013 | `no-public-ingress-by-default` | Accepted |
| 0014 | `observability-stack` | Accepted |
| 0015 | `deploy-by-workflow` | Accepted |
| 0016 | `state-in-cloud-storage` | Accepted |
| 0017 | `secrets-out-of-state` | Accepted |
| 0018 | `db-connection-budget` | Accepted |
| 0019 | `gcp-is-a-standalone-environment` | Accepted |
| 0020 | `contract-validation-over-port-forward` | Accepted |
| 0021 | `images-from-ghcr` | Accepted |
| 0022 | `no-iam-administration-for-the-apply-account` | Accepted |
| 0023 | `proof-of-delivery-is-spelled-out` | Accepted |
| 0024 | `seed-by-workflow` | Accepted |
| 0025 | `approval-on-every-workflow` | Accepted |
| 0026 | `no-direct-push-to-dev` | Accepted |
| 0027 | `destroy-workflow-per-cost-bearing-resource` | Accepted |
| 0028 | `finops-budget-and-cost-export` | Accepted |
| 0029 | `workload-bindings-follow-the-cluster` | Accepted |
| 0030 | `db-init-runs-the-app-image` | Accepted |
| 0031 | `ui-url-through-a-regional-load-balancer` | Accepted |

## ADR-0001: one-app-three-clouds

**Status:** Accepted

**Context:** `shiptrack-modern` runs on AWS and, by the Azure design, on Azure. The goal is to run the same application on GCP too. The application is tied to `boto3` in five modules. The Azure design plans a `SHIPTRACK_CLOUD` setting that selects an implementation for each.

**Decision:** Keep one application and one image. `SHIPTRACK_CLOUD` takes `aws` (default), `azure`, or `gcp`. GCP adds its implementations behind the seam the Azure work defines, so the seam is built once. The chart gains `gcp` as a third value of `cloud`. The API contract and the UI stay frozen.

**Consequences:** All app changes are separate pull requests in `shiptrack-modern` that leave AWS and Azure behavior alone, and the AWS render stays byte-identical. The image carries all three clouds' client libraries, so its size is re-measured. This repository holds no application code.

## ADR-0002: github-oidc-and-workload-identity-federation

**Status:** Accepted

**Context:** The user will use GitHub OIDC. The organization forbids creating or uploading service account keys, so a key is not an option even if wanted. The user is Owner on the project and administers the organization, so role grants and federation are possible, which is unlike Azure.

**Decision:** GitHub Actions authenticates through a Workload Identity pool and an OIDC provider for GitHub, and impersonates one of three service accounts: `shiptrack-plan` (pull request checks, read-only), `shiptrack-apply` (Terraform, environment `dev`), and `shiptrack-deploy` (Helm, environment `dev`). Each binding names one exact subject, not a repository: `apply` and `deploy` are reachable only from the `dev` environment, and `plan` only from the `ci` environment (ADR-0025); each needs the user's approval. The subjects use the immutable format that the AWS repositories already use, `repo:<owner>@<owner id>/<repo>@<repo id>:<suffix>`, built from the workflow context. The provider's attribute condition matches the repository and owner by numeric ID, so a renamed or transferred repository, or any other repository, cannot authenticate. A seed account `shiptrack-seed`, reachable only from the `seed` environment, applies the seed root (ADR-0024).

**Consequences:** No long-lived GCP credential exists in GitHub or git. The pool, provider, seed account, and GitHub environments are created by hand once (design §8.0, `terraform/seed/README.md`). The state bucket, the other accounts, their trust, and their permissions come from the seed workflow. Service accounts are named `shiptrack-<purpose>`; the AWS `<PREFIX>` rule does not apply. `apply` and `deploy` share the `dev` subject, so the environment's deployment-branch rule (only the reviewed `dev` branch) is what separates them from a workflow on another branch, as on AWS (design risk G-R15). The subject format for this repository is confirmed before the first run **[VERIFY]**.

## ADR-0003: tags-and-labels

**Status:** Accepted

**Context:** Every resource in the project must carry `environment: dev` and `name: shiptrack`. The organization already has an `environment` tag key with the values `dev`, `stage`, and `prod`, bound to the folder `dev`, so the project inherits `environment: dev`. The only existing `name` tag key belongs to another project, which a different workload uses, and its value is bound to the folder.

**Decision:** Create a new organization-level tag key `name` with the value `shiptrack`, and bind it to this project. Never use the other `name` key for this project. Tags sit on the project and apply down the hierarchy. Terraform also sets the labels `environment = "dev"` and `name = "shiptrack"` on every resource that takes them, from one `local.labels` map, because labels are what the billing export groups by.

**Consequences:** The effective tags on the project are `environment: dev` and `name: shiptrack`. Open: the folder `dev` also binds a landing-zone `name` tag from the other key, so this project inherits that value as well. Removing or moving that binding changes a shared folder and is the user's decision. Whether inherited tags appear in the billing export, or only labels, is checked **[VERIFY]**.

## ADR-0004: cost-is-a-design-constraint

**Status:** Accepted

**Context:** The user asked for the most cost-effective cluster and the most cost-effective resources.

**Decision:** For every resource, choose the cheapest option that meets this design and the security rules, and record its approximate monthly cost and the alternatives in the ADR. Prefer free tiers (Pub/Sub, Secret Manager, Cloud Storage in `us-central1`, the GKE cluster credit), per-request billing over idle capacity, and Spot capacity. The target baseline is about $25 to $35 a month with no public address (design §13).

**Consequences:** Reliability is traded for cost where the environment is a dev environment: a zonal shared-core database, Spot pods, no high availability. Each trade is a recorded risk. The real cost is measured from the billing export and reported honestly.

## ADR-0005: gke-autopilot-with-spot-pods

**Status:** Accepted

**Context:** The GKE management fee is $0.10 per cluster-hour, and a $74.40 monthly credit per billing account covers one Autopilot or zonal cluster. This project is the only one on its billing account, and no other project there has a cluster. The workload requests about 0.65 vCPU and 0.9 GiB (design §7.2).

| Option | Compute per month | Notes |
|---|---|---|
| Autopilot, Spot pods | $5 to $10 | Pay for requests only, no node to size or patch. Spot is 60% to 91% off |
| Autopilot, on-demand | about $24 | $0.0445 per vCPU-hour and $0.0049 per GiB-hour |
| Standard zonal, one `e2-standard-2` Spot node | about $15 to $20 with a small boot disk | Pays for idle capacity; the node must also fit GKE's system pods |
| Standard zonal, `e2-medium` Spot node | about $7 | The workload plus system pods exceed its allocatable CPU |

**Decision:** GKE Autopilot with every workload on Spot pods (`cloud.google.com/gke-spot: "true"`), a `spot` value to turn it off. Autopilot does not bill for system pods, scales its nodes to the pods, and enforces a restricted security baseline by default.

**Consequences:** Spot capacity can be reclaimed at any time, so both api replicas can go together for a short outage (risk G-R2). Spot pods can also stay Pending when capacity is short, which would time out a `--atomic` deploy and roll it back **[VERIFY how often]**. If preemption or Pending pods hurt, `spot: false` costs roughly $15 to $19 more a month. Workers are idempotent, so a cut-off message is redelivered and applied once. Autopilot rounds requests up to its minimums, which can raise the bill (risk G-R14). Prices and minimums are checked against the pricing page **[VERIFY]**. An Arm compute class may be cheaper and is tested after the first deploy **[VERIFY]**.

## ADR-0006: region-us-central1

**Status:** Accepted

**Context:** Prices differ by region. `us-central1` is among the cheapest, and Cloud Storage's free allotment applies only in `us-central1`, `us-east1`, and `us-west1`. The environment is for a dev demonstration, with no data-residency requirement and no latency need.

**Decision:** Use `us-central1` for every resource, set by one variable.

**Consequences:** Montréal or Toronto would sit closer to the Azure cluster but cost more **[VERIFY]**. Changing the region later means recreating the cluster and database.

## ADR-0007: private-nodes-and-cloud-nat

**Status:** Accepted

**Context:** The parent rules forbid public instance addresses. Nodes need to reach GHCR for images, GitHub, and Google APIs. Cloud NAT costs $0.0014 per VM-hour up to 32 VMs, about $0.005 per hour for the gateway's address, and $0.045 per GiB, about $4 to $6 a month at this size. Giving nodes public addresses would cost about the same per node and expose them.

**Decision:** Private nodes, one Cloud NAT gateway with automatic address allocation, and Private Google Access on the subnet. The control plane is reached through the DNS-based endpoint, authenticated by IAM, with the IP-based public endpoint off, so no allow-list of addresses exists to keep or leak.

**Consequences:** NAT is a small fixed cost even with no traffic (risk G-R10). Anyone with the right IAM permission can reach the control plane from any network, and IAM is the gate (risk G-R8). The permission the DNS endpoint needs is checked **[VERIFY]**.

## ADR-0008: cloud-sql-shared-core-private-ip

**Status:** Accepted

**Context:** The application needs PostgreSQL, and the code uses `psycopg`, so a managed Postgres keeps it unchanged. Options:

| Option | Per month | Notes |
|---|---|---|
| Cloud SQL `db-f1-micro`, Enterprise edition, zonal | $10 to $13 | Shared core, 0.6 GB memory, no SLA, managed backups and patching |
| Cloud SQL dedicated-core | $50 or more | Not needed at this scale |
| Postgres in the cluster on Spot pods | about $4 to $5 | Saves $6 to $8 but loses managed backups, and a Spot reclaim takes the database down |

**Decision:** Cloud SQL for PostgreSQL 17, `db-f1-micro`, with `edition = ENTERPRISE` set explicitly because the default may be Enterprise Plus **[VERIFY]**. Zonal, 10 GiB, private IP only through private services access, `ssl_mode = ENCRYPTED_ONLY`, daily backups kept 7 days, point-in-time recovery off, deletion protection on. No public IP, so no address charge. Roles and grants are created by the `db-init` Job.

**Consequences:** A shared-core instance has a low connection limit (ADR-0018) and no SLA (risk G-R3). A zone outage is an outage (risk G-R4). The in-cluster database is the cheaper alternative if cost matters more than data safety; it is not chosen.

## ADR-0009: pubsub-for-queues-and-notifications

**Status:** Accepted

**Context:** AWS uses SQS with a DLQ, and EventBridge with a rule and a 7-day archive. Pub/Sub's first 10 GiB a month are free, and it has pull subscriptions, dead-letter policies, attribute filters, and topic retention with seek.

**Decision:** Events: topic `shiptrack-carrier-events` with one pull subscription (ack deadline 60 s, retention 4 d, dead-letter after 5 attempts to a dead-letter topic with its own pull subscription kept 14 d). Notifications: topic `shiptrack-notifications` with 7-day retention and a subscription filtered on the attribute `detail_type`, with the same dead-letter setup. The publisher sets `idempotency_key` and `detail_type` as attributes. The Pub/Sub service agent gets the roles that dead-lettering needs.

**Consequences:** Pub/Sub delivers at least once; the worker's `ON CONFLICT` makes that safe (risk G-R9). Unlike Azure, replay survives through topic retention. Filters match attributes only. The Pub/Sub emulator supports the filter and the dead-letter policy as used here, and the application's emulator tests exercise both (modern ADR-0032).

## ADR-0010: secret-manager-and-workload-identity

**Status:** Accepted

**Context:** Service account keys are forbidden. Secret Manager gives six active versions and 10,000 accesses a month free. GKE can grant roles directly to a Kubernetes service account as an IAM principal, with no Google service account.

**Decision:** Database credentials live in Secret Manager as JSON with the same shape as the AWS secret. Each workload's Kubernetes service account is bound directly to the single secret it reads (`secretAccessor`), and to the Pub/Sub and Storage resources it uses (design §7.3). Passwords are written with write-only arguments from an ephemeral random value (ADR-0017). The one exception to "no Google service account" is the signer (ADR-0011).

**Consequences:** No Kubernetes Secret and no key exists. A binding per workload per resource means many bindings, written once by `modules/workload-access`. Rotation is a new secret version plus the existing refetch-once behavior.

## ADR-0011: cloud-storage-and-signed-urls

**Status:** Accepted

**Context:** Proof of delivery is stored in S3 and downloaded through a `302` to a presigned URL. Signing a URL needs a private key or the IAM signing API, and keys are forbidden. Cloud Storage's first 5 GiB in `us-central1` are free.

**Decision:** One bucket named `shiptrack-proof-of-delivery-<random suffix>` in `us-central1`, Standard class, uniform access, public access prevention enforced, with objects under `proof-of-delivery/{shipment_id}/{document_id}` and stored as `gs://` URIs. The setting is `SHIPTRACK_PROOF_OF_DELIVERY_BUCKET` (ADR-0023). The api uploads with its own principal (`storage.objectUser`). For downloads it asks the IAM signing API to sign a V4 URL, valid 300 s, as the service account `shiptrack-proof-of-delivery`, which holds only `storage.objectViewer` on the bucket. The api holds `serviceAccountTokenCreator` on that one account. The seed root creates the account (ADR-0022).

**Consequences:** A leaked signed URL can only read one object for five minutes. The signer is the single Google service account used by a workload. Signing from a pod with no service account of its own, and the roles it needs, are checked **[VERIFY]**.

## ADR-0012: fixed-replicas-without-keda

**Status:** Accepted

**Context:** AWS scales workers with KEDA on queue depth, including scale-to-zero for worker-notify. KEDA runs three pods that request about 0.3 vCPU and 0.3 GiB, about $3 a month on Spot pods. Keeping worker-notify at one replica costs about $0.60. KEDA's Pub/Sub scaler reads Cloud Monitoring, which adds a delay of a minute or more.

**Decision:** No KEDA on GCP. api has 2 replicas, worker-events 1, worker-notify 1, with no HPA. The chart gets `scaling.mode: fixed`, which renders neither KEDA objects nor an HPA.

**Consequences:** About $2.50 a month saved and three fewer components. There is no scale-to-zero and no burst scaling, so a large backlog drains at one worker's pace. This also bounds database connections (ADR-0018). Optimization O-M3 in modern's design does not apply. If load grows, adding KEDA is a chart value and a Helm release.

## ADR-0013: no-public-ingress-by-default

**Status:** Accepted. The optional Gateway it describes was built, as a regional load balancer with the allow-list it asked for, in ADR-0031.

**Context:** Any public address on GCP goes through a load balancer forwarding rule at $0.025 per hour, about $18 a month, which is more than the compute. Restricting it to allow-listed addresses needs Cloud Armor, about $6 more **[VERIFY both]**. GCP is a standalone environment outside the AWS cutover (ADR-0019), so nothing requires an address.

**Decision:** No public address by default. The api is a `ClusterIP` service. Operators open the UI and API with `kubectl port-forward` through the DNS endpoint, which needs IAM permission only. The contract run uses the same path (ADR-0020). The chart and the `addons` root can create a regional external Application Load Balancer through Gateway API when `gateway_enabled` is true. Enabling it is its own pull request, with its own ADR for the domain, TLS certificate, and Cloud Armor allow-list; the allow-listed CIDR goes in a masked secret and never becomes a `for_each` key.

**Consequences:** Saves about $18 to $24 a month. A port-forward gives the operator `http://localhost:<port>/ui/` on their own machine, for as long as the command runs. It is not a URL that anyone else can open, so the UI is not reachable by people without cluster access, which limits demonstrations. The network policy allows Google's health-check and proxy ranges only when the Gateway is on.

**Demonstrations.** Only the operator opens the app, so the demo is given from the operator's machine: `kubectl port-forward` to the api service, at no extra cost. The Gateway is not built. It is revisited only if a port-forward through the cluster's DNS endpoint turns out not to work for the demo, or if someone else needs to open the app; it would then be its own pull request and ADR, with a domain and a certificate, and enabled only for the event.

## ADR-0014: observability-stack

**Status:** Accepted

**Context:** AWS uses AMP, a managed scraper, Grafana, and CloudWatch alarms. Managed Service for Prometheus is built into Autopilot and billed per sample. Grafana needs a pod and a data source. Cloud Monitoring dashboards and alert policies need no pods.

**Decision:** Managed Prometheus collects port 9090 through a `PodMonitoring` resource at a 60-second interval. Dashboards and alerts are Cloud Monitoring, from Terraform: queue age and dead-letter depth from Pub/Sub metrics, pod restarts from Kubernetes metrics, the SLA heartbeat from a log-based metric, and an availability burn-rate alert in PromQL. No Grafana. Notifications go to one channel whose address is a masked secret.

**Consequences:** About $2 to $5 a month for samples and alert conditions **[VERIFY]**. Fewer panels than the five AWS Grafana boards. Cloud Logging ingestion should stay inside the free allotment **[VERIFY]**. Whether PromQL alert policies cover the burn-rate rules is checked **[VERIFY]**.

## ADR-0015: deploy-by-workflow

**Status:** Accepted

**Context:** The user asked for workflows with GitHub OIDC. On GCP the deploying identity can be granted what it needs, unlike Azure. Flux would add about four controllers to the cluster, about $2 to $3 a month on Spot pods, and a second delivery path.

**Decision:** A `deploy-app` workflow runs Helm with `--atomic` after environment approval, as AWS does. It authenticates as `shiptrack-deploy`, which holds only the permission to fetch credentials; every cluster permission is Kubernetes RBAC in the `shiptrack` namespace. The digest is a dispatch input. The chart comes from `shiptrack-modern` at a commit SHA pinned in `deploy/chart-ref`.

**Consequences:** GitHub holds no long-lived credential, and the cluster is reachable from CI only through IAM. A deploy is a manual dispatch, because `workflow_run` cannot span repositories. Never `kubectl apply` or `helm upgrade` by hand.

## ADR-0016: state-in-cloud-storage

**Status:** Accepted

**Context:** Terraform needs a backend. The `gcs` backend locks natively. The organization requires uniform bucket access. The AWS platform creates its state bucket from its `apply-bootstrap` workflow, and the user asked for the same here (ADR-0024).

**Decision:** One bucket, `shiptrack-tfstate-<project number>`, in `us-central1`, created and managed by the seed root: uniform access, public access prevention enforced, versioning on with the newest ten versions kept, Google-managed encryption, the shared labels, `prevent_destroy`. The name comes from the project number, so it is unique without a random suffix, and `scripts/ci.sh` derives it the same way. One state object per root, in the default workspace: `gcp/<root>/default.tfstate`. The bucket name reaches Terraform through a gitignored `backend.tf` that the script writes on the runner. Only the seed, plan, and apply accounts can reach the bucket; the plan account only reads it.

**Consequences:** The state holds no secret values (ADR-0017). Cost is effectively zero. Versioning keeps old state for recovery. The apply account's project-level storage admin role also covers this bucket, which design risk G-R5 records. The bucket name contains the project number, so it is masked in logs.

## ADR-0017: secrets-out-of-state

**Status:** Accepted

**Context:** The parent rules keep secret values out of Terraform state with ephemeral and write-only arguments (Terraform 1.11 or later). Unlike Azure, no GCP resource in this design exposes a key or connection string as an attribute.

**Decision:** Database passwords come from an ephemeral random value and are written to Cloud SQL and Secret Manager with write-only arguments, with a version integer to rotate. There is no recorded exception.

**Consequences:** The state is not a credential. The provider's minimum version for each write-only argument is checked with `terraform validate` against the pinned version **[VERIFY]**.

## ADR-0018: db-connection-budget

**Status:** Accepted

**Context:** `db-f1-micro` has a small `max_connections`; the default is derived from memory, and the PostgreSQL value is not in the documentation that was reachable **[VERIFY with `SHOW max_connections` after the first apply]**. The Azure design budgets 21 connections for a similar server.

**Decision:** A budget of 21 connections, with api at 2 replicas and worker-events at 1 (ADR-0012):

| Consumer | Replicas | Connections each | Total |
|---|---|---|---|
| api (pool 4, overflow 2) | 2 | 6 | 12 |
| worker-events (pool 2) | 1 | 2 | 2 |
| sla-scan | 1 | 2 | 2 |
| migrate | 1 | 2 | 2 |
| **Total** | | | **18** |

A check in `ci-checks` reads the pool settings and replica counts in `deploy/values-gcp.yaml` and fails if the sum exceeds the budget. This repository has no Python test setup, so the check is a small script. If the measured limit is lower than the budget plus the superuser reserve, either set the `max_connections` flag or move up a tier.

**Consequences:** Replica counts are fixed (ADR-0012), so the arithmetic holds. Raising replicas or pools means re-running it.

## ADR-0019: gcp-is-a-standalone-environment

**Status:** Accepted

**Context:** The AWS cutover moves traffic between legacy and modern by ALB weights in `shiptrack-platform`. The GCP environment would need a public address and a path from the ALB to join the cutover, and a database shared with RDS would need a cross-cloud connection. The user chose a new database of its own.

**Decision:** GCP is its own environment with its own new Cloud SQL database, outside the cutover. The platform ALB weights are not touched. Schema ownership is this environment's, so `migrations.enabled` is true and the SLA scan is active, because there is no legacy to hand over from. Nothing here changes AWS behavior.

**Consequences:** No data moves from RDS; the GCP database starts from the Alembic migrations. No traffic shifting between AWS and GCP. Joining the cutover later would be a new decision and a platform pull request.

## ADR-0020: contract-validation-over-port-forward

**Status:** Accepted

**Context:** The contract suite sends routing headers that steer the AWS load balancer. With no public address (ADR-0013), a runner cannot reach the api directly.

**Decision:** `ops-contract` runs on a GitHub-hosted runner as `shiptrack-deploy`, opens `kubectl port-forward` to the api service, and runs the suite with `BASE_URL=http://localhost:<port>`, `TARGET=modern`, an empty `TEST_TOKEN`, and `SINGLE_STACK=1`. The AWS token is never sent. The deploy account may port-forward in the namespace through Kubernetes RBAC (`pods/portforward`); whether GKE also requires an IAM permission for it is checked **[VERIFY]**.

**Consequences:** The suite needs no change and no address is exposed. The workflow needs approval because it creates synthetic shipments. If the Gateway is enabled, the suite can run against its address instead.

## ADR-0021: images-from-ghcr

**Status:** Accepted

**Context:** The user wants the same app on all three clouds. ECR is same-account pull only. The Azure design already publishes the merged multi-arch image to GHCR as a public package.

**Decision:** GCP pulls the image from GHCR by digest, the same digest that runs on AWS and Azure. No Artifact Registry repository is created. The publish step is one pull request in `shiptrack-modern`, shared with Azure.

**Consequences:** One build and one scan serve all three clouds. Image pulls go through Cloud NAT (ADR-0007). A pull-through cache in Artifact Registry is not used, because it would add a resource for a few cents of NAT traffic.

## ADR-0022: no-iam-administration-for-the-apply-account

**Status:** Accepted

**Context:** The AWS stack gives every role a permission boundary. An apply account that could create service accounts or edit project IAM could escalate itself, for example by impersonating the seed account. Limiting such grants with an IAM condition on resource names or granted roles depends on syntax that was not verified for service accounts.

**Decision:** Remove the need instead of limiting it. The seed root creates every service account once (plan, apply, deploy, node, and proof-of-delivery signer) and makes every project-level grant. The apply account holds admin roles for the services it manages and nothing that edits project IAM or creates service accounts. Its two exceptions are single-resource: `serviceAccountUser` on the node account, so the cluster can use it, and `serviceAccountAdmin` on the proof-of-delivery signer, so the api can be allowed to create tokens for it. Grants on topics, subscriptions, secrets, and buckets come from each service's own admin role. The apply account is reachable only through the `dev` environment (ADR-0002).

**Consequences:** A bad plan cannot grant itself ownership or reach the seed account. A new workload that needs a new service account, or a project-level role, means a change to the seed root and an `apply-seed` run. The apply account's storage admin and cluster admin roles remain broad (design risk G-R5). An IAM-condition boundary is a possible later hardening **[VERIFY]**.

## ADR-0023: proof-of-delivery-is-spelled-out

**Status:** Accepted

**Context:** Modern's ADR-0030 separates two meanings: a pod is a Kubernetes pod, and the document a carrier produces on delivery is a proof of delivery, never abbreviated `POD`. It kept the names that stored data, other repositories, deployed resources, or the frozen contract already depend on: the `/pod` API paths, the `pod_documents` table, the `pod/` key prefix, the `SHIPTRACK_POD_BUCKET` setting, the `shiptrack_pod_*` metrics, and the `pod_not_migrated` log events. The GCP environment is new, so it has no deployed names to keep.

**Decision:** Every new GCP name spells the document out:
- the bucket `shiptrack-proof-of-delivery-<random suffix>` and its object prefix `proof-of-delivery/`;
- the settings `SHIPTRACK_PROOF_OF_DELIVERY_BUCKET` and `SHIPTRACK_PROOF_OF_DELIVERY_SIGNER`;
- the service account `shiptrack-proof-of-delivery`, which signs download URLs;
- Terraform resource and module names, labels, descriptions, alert and dashboard titles, and the chart's GCP values (`proofOfDelivery…`).

`pod` stays only a Kubernetes pod: pod security, pod restarts, `podSelector`, pod names. Names that the shared code and schema require are not changed for GCP alone: the `pod_documents` table (one Alembic lineage), the `/pod` API paths (frozen contract), and the metric and log-event names (shared dashboards and tests). The AWS setting `SHIPTRACK_POD_BUCKET` is untouched, so AWS behavior does not change.

**Consequences:** The new cloud implementation adds its own explicit setting next to the kept one, so the settings class carries both until a later, separate rename in modern. A reader who sees `pod` in this repository reads it as Kubernetes. This repository's documents follow the same rule.

## ADR-0024: seed-by-workflow

**Status:** Accepted

**Context:** The first apply needs a state bucket, service accounts, trust, and permissions, and none of them can be created by the pipelines that depend on them. The AWS platform solves this with a hand-made seed role and an `apply-bootstrap` workflow that creates the state bucket, the permission boundary, and the deploy roles. The user asked for the same on GCP: a seed workflow that creates the Terraform state bucket, the permission policies, and the trust relationship policies.

**Decision:** The `apply-seed` workflow applies `terraform/seed` as `shiptrack-seed`. It has two jobs in the `seed` environment, plan and apply, each needing the user's approval, so the plan summary (addresses and actions, never values) is read before anything is applied. It creates the state bucket, the project's APIs, the five service accounts, the trust bindings that let GitHub subjects impersonate three of them, and their role bindings (design §8.1). On the first run `scripts/ci.sh` creates only the bucket with local state, writes `backend.tf`, and migrates the state into the bucket before creating the rest, as on AWS. The user creates the pool, provider, seed account, and GitHub environments by hand once, with the commands in `terraform/seed/README.md`. The workflow runs only on `dev`; its actions are pinned to commit SHAs; it uploads no plan file.

**Consequences:** Nothing is applied from a workstation. Everything after the by-hand step is reviewed and approved in GitHub. The first approval covers creating the bucket if it is missing, and the summary of the first run lists only that bucket. A failure between creating the bucket and migrating the state is recoverable from the README. The workflow was validated locally with `actionlint`, `terraform validate`, and an offline plan with dummy identifiers; its first real run is the first test of the runner's `gcloud` credentials and of the subject format **[VERIFY]**.

## ADR-0025: approval-on-every-workflow

**Status:** Accepted

**Context:** The user wants every workflow in this repository to wait for their approval, including pull request checks. The design had `ci-checks` and `ci-terraform` run on pull requests with no environment, and `shiptrack-plan` trusted the `:pull_request` and `:ref:refs/heads/dev` subjects, which no approval gates. The `dev` and `seed` environments admit only the `dev` branch, so a pull request run cannot use them: its ref is a pull request ref.

**Decision:** Add a third environment, `ci`, with the user as required reviewer and no deployment-branch rule. Every job of `ci-checks` and `ci-terraform` runs in `ci`. `shiptrack-plan` trusts one subject, `…:environment:ci`, in place of the two it had, so no job reaches any service account without an approval. The `workflows` job in `ci-checks` fails any workflow job that names no `environment:`. `github-setup.sh` creates `ci`, and the plan account's secrets live in `ci`. The other approval settings stay: `dev` and `seed` for applies and deploys, and approval for every outside contributor's workflow.

**Consequences:** Pull request checks are pending until approved, once per workflow run for the jobs that wait together. A new push needs a new approval, and Dependabot's pull requests wait too. The approval is the user's, so the review of a pull request's workflow changes happens before its code runs with the plan account's token. Because `ci` has no branch rule, a pull request that edits a workflow can ask for the plan account once approved, which is why the user reads the workflow diff before approving, and why the plan account is read-only. Fork pull requests get no OIDC token and no environment secrets, so they can run only the checks that need none. Whether an environment with no branch rule accepts pull request refs, and whether jobs of one run approve together, is checked on the first pull request **[VERIFY]**.

## ADR-0026: no-direct-push-to-dev

**Status:** Accepted

**Context:** `dev` is the integration branch, and the `dev` and `seed` environments admit only it. Whatever reaches `dev` can be applied to GCP after an approval, so an unreviewed push to `dev` would put unreviewed code in front of the approvals. The platform repository already protects `dev`; this repository had no protection.

**Decision:** Protect `dev` with a branch protection rule: changes arrive only by pull request, administrators included (`enforce_admins`), with no force push, no deletion, and conversations resolved before merge. The rule requires no approving review, because the user is the only reviewer and cannot approve their own pull request, and it requires the `ci-checks` jobs `terraform`, `secrets`, and `workflows`. `ci-terraform`'s check is added with `--check` when that workflow exists (design §10). `terraform/seed/scripts/github-setup.sh` holds the same settings, so a re-run keeps the rule.

**Consequences:** Every change, including the user's, goes through a short-lived branch and a pull request, as the parent rules already require. There is no bypass for an emergency fix; the rule has to be loosened in the GitHub settings first and restored after. Pull requests are still merged by the user, so the rule stops accidents and unreviewed pushes, not the user's own merge.

## ADR-0027: destroy-workflow-per-cost-bearing-resource

**Status:** Accepted

**Context:** The user wants every resource that is provisioned to have a way to be taken down again, because the cost starts when a root is applied and stops only when its resources are gone. Terraform destroys by address or by root, and no `apply-` workflow can remove anything on its own. The design set protections that stop an accidental delete: `deletion_protection` on Cloud SQL and the cluster, and `prevent_destroy` on the state bucket. The parent rules have no workflow category for destroying.

**Decision:** Every pull request that provisions a cost-bearing resource also adds that resource's destroy workflow. A resource group is cost-bearing when it appears in the cost table (design §13) or holds data. The groups and their workflows are:

| Workflow | Takes down | Root |
|---|---|---|
| `destroy-addons` | Namespace, deploy RBAC, and the Gateway if enabled | addons |
| `destroy-cluster` | GKE Autopilot cluster | cluster |
| `destroy-cloud-sql` | Cloud SQL instance, database, and users | data |
| `destroy-network` | VPC, subnet, router, Cloud NAT, and private services access | data |
| `destroy-pubsub` | Topics, subscriptions, and dead-letter topics | data |
| `destroy-proof-of-delivery-storage` | The proof-of-delivery bucket and the signer's binding on it | data |
| `destroy-secrets` | Secret Manager secrets | data |
| `destroy-monitoring` | Alert policies, the notification channel, and the dashboard | data |

Workload IAM bindings go with the resource they bind. The seed root has no destroy workflow: the state bucket, the service accounts, and the trust are never destroyed by a workflow.

The category `destroy-` joins the parent rules: Terraform destroy of one resource group, environment approval. Each workflow is thin: it names its root, its target addresses, and a confirmation value, and calls one shared script under `.github/scripts/`. It runs as `shiptrack-apply` in the `dev` environment, so no new account and no new trust exist. Its `concurrency` group is the one `apply-terraform` uses, so a destroy and an apply never touch the same state together.

Each run has two jobs, both in `dev` and each needing the user's approval, as `apply-seed` does:
1. **plan** runs `terraform plan -destroy -target=…` and prints the addresses and actions that would be destroyed, including the dependents Terraform adds to a targeted destroy, and never values. It fails unless the dispatch input `confirm` equals the workflow's resource name.
2. **destroy** makes a fresh plan and applies it from the same job. No plan file is uploaded.

The protections are lowered inside the approved run, never left off. Resources use their provider attributes (`deletion_protection`, `force_destroy`) from variables that default to protected. Before the destroy, the job applies the targeted change with the variable set to unprotected, because the provider reads the stored value on delete, then destroys. A normal apply sets the protection back for anything that remains. `prevent_destroy` is not used on resources that have a destroy workflow, because a lifecycle argument cannot be switched by a run. It stays on the state bucket, which is outside every destroy workflow.

**Consequences:** Spend can be stopped one group at a time, by two approvals and a typed name, and the cluster or database can be removed without touching the rest. Destroying a group that another root depends on fails at Google, not silently: remove them in reverse order (addons, cluster, then the data groups, with Cloud SQL before the network). Destroying Cloud SQL deletes its data and its backups; its summary says so. A deleted Cloud SQL instance name cannot be reused for some time **[VERIFY]**, so the instance name carries a random suffix. A non-empty bucket is deleted only because the run sets `force_destroy`, which is why the storage workflow exists separately. `-target` is the documented tool for this and is used only here, never in `apply-terraform`. Whether `-destroy -target` with an in-run unprotect behaves as described for each resource type is checked when each workflow is first built **[VERIFY]**. The `workflows` CI job already enforces that each destroy workflow names an environment and pins its actions.

## ADR-0028: finops-budget-and-cost-export

**Status:** Accepted

**Context:** Cost is a design constraint (ADR-0003), the baseline is about $25 to $35 a month (design §13), and every figure there is a remembered price marked [VERIFY]. Nothing yet tells the owner when the real bill leaves that range, or records what it is. This project is the only one on its billing account, so the account's spend is the project's spend. The labels `environment` and `name` are on every resource that takes them (ADR-0003) so that the bill can be grouped by them.

**Decision:** Three pieces, none of which can create spend of its own:
- **A budget with alerts.** A Cloud Billing budget of $50 a month on this project, which is about 1.5 times the baseline. It alerts at 50% ($25), 90% ($45), and 100% ($50) of actual spend, and at 100% of forecast spend. Credits count, so the GKE free-tier credit (design §13) reduces the figure the budget watches. Alerts go to an email notification channel whose address is a masked secret, and also to the billing account's default recipients. A budget alerts and never stops anything.
- **A billing export.** The standard usage cost export goes to a small BigQuery dataset created in Terraform. The export itself is switched on by hand in the billing console, because it is not part of the Terraform provider **[VERIFY]**. `ops-check-cost`, a read-only workflow, queries the dataset and prints the month's cost by service and by the `name` label to its summary. `docs/cost/analysis.md` is written from it after the build (design §13).
- **A separate root.** Both live in `terraform/finops`, not in `data`, so that taking the data groups down does not remove the budget or the cost history. It has no destroy workflow, like the seed root: a budget and a month of billing rows are not what a destroy workflow is for.

Two roles on the billing account are granted by hand, once, because billing account permissions are outside the project and the seed root cannot give them: `roles/billing.costsManager` to `shiptrack-apply` (it creates the budget) and `roles/billing.viewer` to `shiptrack-plan` (it reads the budget when planning); the plan of the applied root confirmed that this role reads the budget. The seed root adds `bigquery.googleapis.com` and `billingbudgets.googleapis.com` to the enabled APIs, `roles/bigquery.admin` to the apply account for the dataset, and `roles/bigquery.jobUser` to the plan account for the queries. The dataset gives the plan account `roles/bigquery.dataViewer` on it only.

No automatic stop. A rule that scales the cluster to zero or detaches billing when a budget is crossed needs a Pub/Sub trigger, a function, and an account that can change billing, and it can take down a demo that has to stay up. The owner gets the alert and runs the `destroy-` workflows (ADR-0027).

**Consequences:** Alerts arrive after the money is spent, with up to a day of delay in the billing data. The budget and the cost history survive a full teardown. BigQuery storage for one project's rows is far under the 10 GiB free tier, and the queries are far under the free 1 TiB a month **[VERIFY]**. Two by-hand grants and one by-hand console step are the price of keeping billing permissions off the pipelines. The email address sits in the state bucket as a channel label, which only the three pipeline accounts can read.

## ADR-0029: workload-bindings-follow-the-cluster

**Status:** Accepted

**Context:** ADR-0010 gives each workload's Kubernetes service account direct IAM roles on the single resource it uses, with no Google service account. The principal for such an account sits in the project's workload identity pool, `<PROJECT_ID>.svc.id.goog`, and Google creates that pool when the first cluster with Workload Identity is created. An IAM policy that names a principal in a pool that does not exist yet can be refused, which would fail an apply of the data root partway through **[VERIFY with the first cluster]**. The design (§8.2) listed the bindings in the data root, which is applied before the cluster.

**Decision:** The data root creates the resources and no workload binding. The bindings are made by the cluster root, in `modules/workload-access`, one call per row of design §7.3, after the cluster exists. The cluster root reads the resource names from the data root's outputs through its remote state, which the plan and apply accounts can both read. The exceptions are bindings that name no workload: Pub/Sub's service agent on the dead-letter topics and subscriptions, and the signer's read access to the bucket. They stay with the resource they bind, in the data root.

**Consequences:** A destroy of a data group never leaves a binding behind, because the cluster, and its bindings, come down first (ADR-0027 order: addons, cluster, then the data groups). Recreating the cluster recreates the bindings. The data root can be applied, and paid for, before the cluster exists, with nothing in it that the cluster needs to find. The cluster root now needs a read of the data root's state and permission to set IAM on topics, subscriptions, secrets, and the bucket, which the apply account has through its service admin roles (ADR-0022). If the first cluster shows that the bindings can be made before it exists, they can move into the data root without a change to the workloads.

## ADR-0030: db-init-runs-the-app-image

**Status:** Accepted

**Context:** The design had `deploy-app` run a `psql` Job from `deploy/db-init/init.sql` with the administrator's secret. The Job also has to give the two application roles their passwords, and those are in their own secrets, which `shiptrack-db-init` could not read. A `psql` Job also needs a second image with a way to fetch secrets, and nothing in it could be tested before the cluster. Cloud SQL's administrator is not a superuser and the database is reachable only from the cluster, so the roles cannot be made from a runner.

**Decision:** The Job runs `python -m shiptrack db-init` from the release's own image (shiptrack-modern ADR-0035). The command reads the three credentials through the application's secret source and runs `db/init.sql`, which is in the image. `shiptrack-db-init` is bound as `secretAccessor` on the administrator's, the application's, and the migrator's secrets, each on the single secret. The Job manifest and its service account are in `deploy/db-init/`, and `deploy-app` applies the service account and creates the Job. The roles' connection limits come from the connection budget (ADR-0018): 18 for the application and 3 for the migrator.

**Consequences:** There is one image on every cloud and nothing extra to pull or pin. The command is tested against PostgreSQL in `shiptrack-modern`. The cluster root makes 13 workload bindings instead of 11, two more on the db-init principal, and applying it adds them. A rotation is a raise of `db_credentials_version` in the data root, an apply, and a run of `deploy-app`, whose db-init Job resets both passwords. Cloud SQL's own role setup is proven only by the first run **[VERIFY]**.

## ADR-0031: ui-url-through-a-regional-load-balancer

**Status:** Accepted

**Context:** ADR-0013 left the application reachable only through `kubectl port-forward` and sketched an optional regional load balancer, for a demonstration that needs a URL in a browser, from one person's address. The API has no login, so anyone who can reach it can create and change shipments: the URL must admit only the owner. There is no domain, and a regional external Application Load Balancer can issue a Google-managed certificate only by DNS authorization, which needs a CNAME in the DNS of the hostname. A global load balancer would allow HTTPS on a free sslip.io name, and was considered and declined; the owner chose the regional balancer and plain HTTP.

**Decision:** A regional external Application Load Balancer, created by a GKE Gateway (`gke-l7-regional-external-managed`) with one HTTP listener on port 80, so there is one forwarding rule and no certificate. The URL is `http://<the reserved address>/ui/`. Terraform (the `ui-ingress` module in the data root) creates the subnet the balancer's proxies need (purpose `REGIONAL_MANAGED_PROXY`), reserves a regional external address, and creates a regional Cloud Armor policy that denies everyone and has one allow rule. A regional Gateway requires a regional policy. The Gateway, the route, a health check on `/readyz`, a backend policy that attaches the Cloud Armor policy, and a network policy that admits the balancer's proxies and Google's health checkers to port 8000 are in `deploy/gateway` and are applied by `ops-ui-port`, not by `deploy-app`, so a deploy never starts the balancer's charge. The deploy account's role in the namespace gains those object kinds.

The allow rule holds an unroutable documentation address (192.0.2.1/32) until it is opened. The `ops-ui-port` workflow reads the range from the `GCP_UI_ALLOWED_CIDRS` secret of the `dev` environment, which is masked before any step runs and is never a workflow input, because inputs are shown on a public run page. `open` puts the secret's range in the rule and `close` puts the unroutable one back; `remove` deletes the Gateway so the load balancer and its charge go. Changing the owner's address is a change to the secret (`scripts/ui-access.sh` does it from the owner's machine) and an `open`. Terraform ignores the rule's range. `destroy-ingress` removes the subnet, the address, and the policy, after `remove`.

The monthly budget moves from $50 to $75 (ADR-0028), because the baseline of about $25 to $35 gains about $24.

**Consequences:** Traffic between the browser and the load balancer is not encrypted, so everything the owner does in the UI, and what the API answers, crosses the internet in clear text; the allow-list keeps everyone else out but does not hide the traffic. The application's HSTS stays off, because its base URL is not https. A person who wants encryption later can add a domain and a managed certificate (a DNS authorization and an HTTPS listener), or move to the global balancer, without changing the application. Closed means every request gets 403 from Cloud Armor, and the load balancer is still billed until `remove`. The URL is shown to the owner by `scripts/ui-access.sh url` and never in a public log. The apply account gains `roles/compute.securityAdmin` for the policy, which needs an `apply-seed` run. That the Gateway uses the named regional address and the backend policy takes the regional Cloud Armor policy, and which source ranges the health checks use, are proven only by the first deploy **[VERIFY]**.

## ADR-0032: monitoring-in-the-data-root

**Status:** Accepted

**Context:** ADR-0014 chose Cloud Monitoring alert policies and a dashboard from Terraform, with Managed Prometheus collecting the application's metrics through the chart's `PodMonitoring`. The design lists a `destroy-monitoring` workflow whose group lives in the `data` root. Alerts need the alert address, which the budget already uses (ADR-0028) as a masked secret.

**Decision:** A `monitoring` module in the `data` root holds the notification channel, a log-based counter on the `sla_scan_completed` record, eight alert policies, and the dashboard. The policies are the seven of design section 11 plus a slow-burn availability alert (6 times the budget over 6 h and 30 min, SEV2), which modern's SLO table already has. Queue age and dead-letter depth read Pub/Sub metrics; pod restarts read `kubernetes.io/container/restart_count` in the `shiptrack` namespace; the heartbeat is an absence condition of 15 minutes on the log-based counter; the two burn-rate alerts are PromQL conditions on `http_requests_total` that require both windows to exceed the multiple. Severities use the policies' `severity` field (SEV1 critical, SEV2 error) and a `severity` label. Each alert's documentation names a runbook in `docs/runbooks/`, written after the builds. The `data` root takes `alert_email` like `finops`, so `terraform-ci.sh` and `terraform-destroy.sh` pass `GCP_ALERT_EMAIL` for it, masked, and every destroy workflow on the data root passes the secret. `destroy-monitoring` targets `module.monitoring`; nothing depends on it.

**Consequences:** A second email channel exists beside the budget's, so the monitoring group can be removed without touching the budget, which survives teardown. Alerts need the application to be scraped: the chart's `PodMonitoring` has been in the release since the first deploy, but that Managed Prometheus collects the ops port, and that Cloud Monitoring accepts the PromQL policies, are proven only by the first apply and the validation run **[VERIFY]**. An absence alert never fires if the counter has never had a sample, so the heartbeat starts working after the first scan following the apply. About $2 to $5 a month for samples and conditions **[VERIFY]**.

## ADR-0033: validation-through-the-port-forward

**Status:** Accepted

**Context:** Acceptance criteria 6 and 7 need zero lost events across a deploy and a Spot preemption, and exactly one `sla_alerts` row per breached shipment. The cluster has no inbound path from a runner except `kubectl port-forward` (ADR-0020), the load balancer admits only the owner (ADR-0031), and Cloud SQL is private. A real Spot reclaim cannot be forced, and `deploy-app` installs a release by digest, so a redeploy of the running digest changes nothing.

**Decision:** One `ops-validate` workflow in the `dev` environment, with a scenario. The platform's simulator runs on the runner through a port-forward that restarts whenever its pod is replaced, and verifies its ledger through the API (`verify --base-url`), which needs no database access. `deploy` restarts every Deployment at once, which is what a rollout does to the pods (SIGTERM, grace period, redelivery). `preemption` deletes every api and worker pod with the 25 second grace Autopilot gives a Spot pod, twice; the deploy account's namespace role gains `delete` on pods for this, which widens nothing because it can already delete the Deployments. `sla` sends shipments, some created already late, then creates a Job from the release's own image, through the `db-init` service account, that counts breached shipments against `sla_alerts` and prints counts only. That Job runs the check in Python inside the application image so that no database credential reaches the runner, and `ci-checks` renders and scans it with the other manifests.

**Consequences:** The result is the ledger, not the client's error count: during a restart some requests fail because the tunnel's pod went away, which a load balancer would hide, and these are reported but do not fail the run. A restart is not a redeploy of a new image, and a pod delete is not a node reclaim, so the evidence says what it shows: pods terminated and replaced under load lose nothing. The check reads every breached shipment in the database, so data from earlier runs counts too; `ops-reset-data` in the platform clears it. A run lasts about 3 seconds per event of a shipment, and the defaults send 300 shipments. The workflow creates test data in this environment's database, so it needs the owner's approval like `ops-contract`.
