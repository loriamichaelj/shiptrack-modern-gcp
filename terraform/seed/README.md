# Seed

Creates what every other pipeline needs before it can run: the Terraform state bucket, the project's
APIs, the five service accounts, the trust that lets GitHub jobs act as three of them, and their
permissions.

It is applied **only** by `.github/workflows/apply-seed.yml`, using a seed service account that
you create by hand once. Nothing is applied from a workstation. See `docs/DESIGN.md` for the
design and `docs/ADR.md` for the decisions.

## What it creates

| Resource | Notes |
|---|---|
| State bucket | `shiptrack-tfstate-<project number>`: versioning, uniform access, public access prevention, newest ten versions kept |
| Project APIs | Everything the later roots need |
| `shiptrack-plan` | The `ci` environment (pull request checks). Reads the project and the state; cannot change either |
| `shiptrack-apply` | The `dev` environment. Administers network, cluster, database, queues, secrets, buckets, and monitoring. Cannot change project IAM or create service accounts |
| `shiptrack-deploy` | The `dev` environment. Fetches cluster credentials; every cluster permission is Kubernetes RBAC |
| `shiptrack-gke-node` | Identity of the GKE nodes |
| `shiptrack-proof-of-delivery` | Signs proof-of-delivery download URLs; reads that bucket and nothing else |

## One-time setup

Replace `<ORG>` with your GitHub user or organization (`loriamichaelj`). Project identifiers stay out
of this repository, so the examples read them from your own session. Run these in your terminal; do
not paste their output into an issue, a pull request, or a log.

### 1. Repository and its IDs (GitHub)

The repository is `<ORG>/shiptrack-modern-gcp`. It has no default branch until the first push, so push
the first commit as `dev` and make `dev` the default branch. Then look up the IDs:

```sh
ORG=<ORG>
OWNER_ID=$(gh api users/$ORG --jq .id)
REPO_ID=$(gh api repos/$ORG/shiptrack-modern-gcp --jq .id)
gh api repos/$ORG/shiptrack-modern-gcp/actions/oidc/customization/sub   # check the prefix, below
```

The last command must show `"use_immutable_subject":true` and a `sub_claim_prefix` of
`repo:<ORG>@<OWNER_ID>/shiptrack-modern-gcp@<REPO_ID>`, which is the format every trust binding here uses.
If it does not, stop: the bindings in `trust.tf` would never match.

### 2. APIs, Workload Identity pool, and provider (GCP, by hand)

```sh
PROJECT_ID=<PROJECT_ID>
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')

gcloud services enable iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com \
  cloudresourcemanager.googleapis.com serviceusage.googleapis.com --project "$PROJECT_ID"

gcloud iam workload-identity-pools create github \
  --project "$PROJECT_ID" --location global --display-name "GitHub Actions"

gcloud iam workload-identity-pools providers create-oidc github-actions \
  --project "$PROJECT_ID" --location global --workload-identity-pool github \
  --issuer-uri "https://token.actions.githubusercontent.com" \
  --attribute-mapping "google.subject=assertion.sub" \
  --attribute-condition "assertion.repository_id == '$REPO_ID' && assertion.repository_owner_id == '$OWNER_ID'"
```

The condition matches the repository and its owner by number, so a renamed or transferred repository,
or any other repository, cannot authenticate. Only tokens that pass it reach the bindings below.

### 3. Seed service account (GCP, by hand)

The seed account runs the `apply-seed` workflow and nothing else. It can be used only by a job in the protected
`seed` environment of this repository.

```sh
gcloud iam service-accounts create shiptrack-seed \
  --project "$PROJECT_ID" --display-name "ShipTrack seed"
SEED=shiptrack-seed@$PROJECT_ID.iam.gserviceaccount.com

for role in roles/serviceusage.serviceUsageAdmin roles/iam.serviceAccountAdmin \
            roles/resourcemanager.projectIamAdmin roles/storage.admin; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member "serviceAccount:$SEED" --role "$role" --condition None --quiet >/dev/null
done

gcloud iam service-accounts add-iam-policy-binding "$SEED" --project "$PROJECT_ID" \
  --role roles/iam.workloadIdentityUser --quiet >/dev/null \
  --member "principal://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github/subject/repo:$ORG@$OWNER_ID/shiptrack-modern-gcp@$REPO_ID:environment:seed"
```

The seed account holds powerful roles because the seed root creates service accounts and grants roles.
Terraform does not manage it, so the pipeline cannot modify its own foundation. Narrow or delete it
once the five accounts exist and you no longer need to change the seed root.

### 4. Repository settings (GitHub)

Use `--dry-run` first to see the calls.

```sh
terraform/seed/scripts/github-setup.sh --dry-run --seed-env $ORG/shiptrack-modern-gcp
terraform/seed/scripts/github-setup.sh --seed-env $ORG/shiptrack-modern-gcp
```

It creates the `dev`, `ci`, and `seed` environments with you as the required reviewer. `dev` and
`seed` admit only the `dev` branch; `ci` runs pull request checks, so it has approval and no branch
rule. It protects the `dev` branch so changes arrive by pull request, makes
the default workflow token read-only, requires approval for every outside contributor's workflow,
and turns on secret scanning and push protection.

An environment job's OIDC `sub` claim carries no branch, so the deployment-branch rule is what keeps
a workflow on another branch from requesting an apply account.

### 5. Secrets and variables (GitHub)

The values identify the project, so they are secrets (GitHub masks secrets in logs). The seed values
belong to the `seed` environment, so only jobs there can read them.

```sh
gh secret set GCP_PROJECT_ID  --env seed -R $ORG/shiptrack-modern-gcp --body "$PROJECT_ID"
gh secret set GCP_PROJECT_NUMBER --env seed -R $ORG/shiptrack-modern-gcp --body "$PROJECT_NUMBER"
gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER --env seed -R $ORG/shiptrack-modern-gcp \
  --body "projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github/providers/github-actions"
gh secret set GCP_SEED_SERVICE_ACCOUNT --env seed -R $ORG/shiptrack-modern-gcp --body "$SEED"
gh variable set GCP_REGION -R $ORG/shiptrack-modern-gcp --body us-central1
```

### 6. Merge this to `dev`

The `seed` environment only accepts deployments from `dev`, so the workflow can run only after
this code is on `dev`.

## Running it

1. Actions, then **apply-seed**, then **Run workflow** on `dev`.
2. Approve the **plan** job. Its summary lists each resource and action, never values.
3. If the plan is what you expect, approve the **apply** job.

The first run creates the state bucket with local state, then moves state into the bucket before
creating anything else. Later runs use the bucket directly, and a run with no changes ends with
"No changes".

## Wiring the other workflows

After the first apply, give the repository the accounts the other workflows use. Every workflow runs
in an environment that needs your approval, so each set of values belongs to its environment: the plan
account to `ci` (pull request checks), and the apply and deploy accounts to `dev`.

```sh
sa() { echo "shiptrack-$1@$PROJECT_ID.iam.gserviceaccount.com"; }
PROVIDER="projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github/providers/github-actions"

for s in GCP_PROJECT_ID:"$PROJECT_ID" GCP_PROJECT_NUMBER:"$PROJECT_NUMBER" \
         GCP_WORKLOAD_IDENTITY_PROVIDER:"$PROVIDER" GCP_PLAN_SERVICE_ACCOUNT:"$(sa plan)"; do
  gh secret set "${s%%:*}" --env ci -R $ORG/shiptrack-modern-gcp --body "${s#*:}"
done
for s in GCP_PROJECT_ID:"$PROJECT_ID" GCP_PROJECT_NUMBER:"$PROJECT_NUMBER" \
         GCP_WORKLOAD_IDENTITY_PROVIDER:"$PROVIDER" GCP_APPLY_SERVICE_ACCOUNT:"$(sa apply)" \
         GCP_DEPLOY_SERVICE_ACCOUNT:"$(sa deploy)"; do
  gh secret set "${s%%:*}" --env dev -R $ORG/shiptrack-modern-gcp --body "${s#*:}"
done
```

## Billing (by hand, for the cost budget)

The budget and the cost report need two roles on the billing account. Billing account
permissions are outside the project, so the seed root cannot grant them. Run once, after the first
`apply-seed` that creates the accounts:

```sh
BILLING_ACCOUNT=$(gcloud billing projects describe $PROJECT_ID --format='value(billingAccountName)' | sed 's#billingAccounts/##')
gcloud billing accounts add-iam-policy-binding $BILLING_ACCOUNT \
  --member "serviceAccount:shiptrack-apply@$PROJECT_ID.iam.gserviceaccount.com" --role roles/billing.costsManager
gcloud billing accounts add-iam-policy-binding $BILLING_ACCOUNT \
  --member "serviceAccount:shiptrack-plan@$PROJECT_ID.iam.gserviceaccount.com" --role roles/billing.viewer
```

`costsManager` lets `shiptrack-apply` create the budget. `viewer` lets `shiptrack-plan` read it when it
plans. Neither role can change who has access to the account or link a project to it.

Then give the `ci` and `dev` environments the two values the finops root needs, as secrets:
`GCP_BILLING_ACCOUNT_ID` (the value of `$BILLING_ACCOUNT`) and `GCP_ALERT_EMAIL` (where budget alerts go).

After the finops root is applied, switch on the standard usage cost export in the billing console
(Billing, Billing export, BigQuery export), pointing at the dataset `shiptrack_billing_export` in the
shiptrack project. Terraform creates the dataset; it cannot switch the export on.

## Trust policies

Every service account trusts the GitHub provider through a `workloadIdentityUser` binding on one
exact subject from this table, where the prefix is `repo:<ORG>@<OWNER_ID>/shiptrack-modern-gcp@<REPO_ID>`.

| Service account | Subject suffix |
|---|---|
| `shiptrack-seed` (by hand) | `:environment:seed` |
| `shiptrack-plan` | `:environment:ci` |
| `shiptrack-apply` | `:environment:dev` |
| `shiptrack-deploy` | `:environment:dev` |

Every subject names an environment that needs your approval, so no job reaches an account unapproved.
`apply` and `deploy` share a subject, so either can be requested by any job in the `dev` environment.
The workflows, which reach `dev` only through a reviewed pull request, choose which one they use.
`ci` admits any branch, because a pull request run has a pull request ref; the plan account is
read-only, and you see the run before approving it.

## State layout

Bucket `shiptrack-tfstate-<project number>` in the region, locked with the `gcs` backend's native
lock objects.

| Object | Owner |
|---|---|
| `gcp/seed/default.tfstate` | seed |
| `gcp/data/default.tfstate` | data |
| `gcp/cluster/default.tfstate` | cluster |
| `gcp/addons/default.tfstate` | addons |

## Recovery

- **A failure after "State is now stored remotely"**: re-run the workflow. State is in the bucket, so
  it picks up where it stopped.
- **The run failed while creating the bucket**: nothing is stored yet. If the bucket exists, import
  it from a workstation with credentials, or delete the empty bucket and re-run:
  `terraform import google_storage_bucket.state <bucket-name>` (then re-run the workflow).
- **A stuck lock on the seed state** (`gcp/seed/default.tflock` left behind by a cancelled
  run): delete that one object from the bucket after confirming no run is in progress.
