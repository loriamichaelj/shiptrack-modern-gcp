# bootstrap

Creates what every other pipeline needs before it can run: the Terraform state bucket, the project's
APIs, the five service accounts, the trust that lets GitHub jobs act as three of them, and their
permissions.

It is applied **only** by `.github/workflows/apply-bootstrap.yml`, using a seed service account that
you create by hand once. Nothing is applied from a workstation. See `docs/DESIGN.md` §8 for the
design and `docs/ADR.md` (ADR-0002, ADR-0024) for the decisions.

## What it creates

| Resource | Notes |
|---|---|
| State bucket | `shiptrack-tfstate-<project number>`: versioning, uniform access, public access prevention, newest ten versions kept |
| Project APIs | Everything the later roots need |
| `shiptrack-plan` | Pull requests and the `dev` branch. Reads the project and the state; cannot change either |
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

The seed account runs this bootstrap and nothing else. It can be used only by a job in the protected
`bootstrap` environment of this repository.

```sh
gcloud iam service-accounts create shiptrack-seed \
  --project "$PROJECT_ID" --display-name "ShipTrack bootstrap seed"
SEED=shiptrack-seed@$PROJECT_ID.iam.gserviceaccount.com

for role in roles/serviceusage.serviceUsageAdmin roles/iam.serviceAccountAdmin \
            roles/resourcemanager.projectIamAdmin roles/storage.admin; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member "serviceAccount:$SEED" --role "$role" --condition None --quiet >/dev/null
done

gcloud iam service-accounts add-iam-policy-binding "$SEED" --project "$PROJECT_ID" \
  --role roles/iam.workloadIdentityUser --quiet >/dev/null \
  --member "principal://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github/subject/repo:$ORG@$OWNER_ID/shiptrack-modern-gcp@$REPO_ID:environment:bootstrap"
```

The seed account holds powerful roles because bootstrap creates service accounts and grants roles.
Terraform does not manage it, so the pipeline cannot modify its own foundation. Narrow or delete it
once the five accounts exist and you no longer need to change bootstrap.

### 4. Repository settings (GitHub)

Use `--dry-run` first to see the calls.

```sh
terraform/bootstrap/scripts/github-setup.sh --dry-run --bootstrap-env $ORG/shiptrack-modern-gcp
terraform/bootstrap/scripts/github-setup.sh --bootstrap-env $ORG/shiptrack-modern-gcp
```

It creates the `dev` and `bootstrap` environments with you as the required reviewer and `dev` as the
only branch allowed to deploy, protects the `dev` branch so changes arrive by pull request, makes
the default workflow token read-only, requires approval for every outside contributor's workflow,
and turns on secret scanning and push protection.

An environment job's OIDC `sub` claim carries no branch, so the deployment-branch rule is what keeps
a workflow on another branch from requesting an apply account.

### 5. Secrets and variables (GitHub)

The values identify the project, so they are secrets (GitHub masks secrets in logs). The seed values
belong to the `bootstrap` environment, so only jobs there can read them.

```sh
gh secret set GCP_PROJECT_ID  --env bootstrap -R $ORG/shiptrack-modern-gcp --body "$PROJECT_ID"
gh secret set GCP_PROJECT_NUMBER --env bootstrap -R $ORG/shiptrack-modern-gcp --body "$PROJECT_NUMBER"
gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER --env bootstrap -R $ORG/shiptrack-modern-gcp \
  --body "projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github/providers/github-actions"
gh secret set GCP_SEED_SERVICE_ACCOUNT --env bootstrap -R $ORG/shiptrack-modern-gcp --body "$SEED"
gh variable set GCP_REGION -R $ORG/shiptrack-modern-gcp --body us-central1
```

### 6. Merge this to `dev`

The `bootstrap` environment only accepts deployments from `dev`, so the workflow can run only after
this code is on `dev`.

## Running it

1. Actions, then **apply-bootstrap**, then **Run workflow** on `dev`.
2. Approve the **plan** job. Its summary lists each resource and action, never values.
3. If the plan is what you expect, approve the **apply** job.

The first run creates the state bucket with local state, then moves state into the bucket before
creating anything else. Later runs use the bucket directly, and a run with no changes ends with
"No changes".

## Wiring the other workflows

After the first apply, give the repository the accounts the other workflows use. The plan workflow
runs on pull requests, outside any environment, so its values are repository secrets. Apply and
deploy values belong to the `dev` environment.

```sh
sa() { echo "shiptrack-$1@$PROJECT_ID.iam.gserviceaccount.com"; }
PROVIDER="projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github/providers/github-actions"

for s in GCP_PROJECT_ID:"$PROJECT_ID" GCP_PROJECT_NUMBER:"$PROJECT_NUMBER" \
         GCP_WORKLOAD_IDENTITY_PROVIDER:"$PROVIDER" GCP_PLAN_SERVICE_ACCOUNT:"$(sa plan)"; do
  gh secret set "${s%%:*}" -R $ORG/shiptrack-modern-gcp --body "${s#*:}"
done
for s in GCP_PROJECT_ID:"$PROJECT_ID" GCP_PROJECT_NUMBER:"$PROJECT_NUMBER" \
         GCP_WORKLOAD_IDENTITY_PROVIDER:"$PROVIDER" GCP_APPLY_SERVICE_ACCOUNT:"$(sa apply)" \
         GCP_DEPLOY_SERVICE_ACCOUNT:"$(sa deploy)"; do
  gh secret set "${s%%:*}" --env dev -R $ORG/shiptrack-modern-gcp --body "${s#*:}"
done
```

## Trust policies

Every service account trusts the GitHub provider through a `workloadIdentityUser` binding on one
exact subject from this table, where the prefix is `repo:<ORG>@<OWNER_ID>/shiptrack-modern-gcp@<REPO_ID>`.

| Service account | Subject suffix |
|---|---|
| `shiptrack-seed` (by hand) | `:environment:bootstrap` |
| `shiptrack-plan` | `:pull_request`, `:ref:refs/heads/dev` |
| `shiptrack-apply` | `:environment:dev` |
| `shiptrack-deploy` | `:environment:dev` |

`apply` and `deploy` share a subject, so either can be requested by any job in the `dev` environment.
The workflows, which reach `dev` only through a reviewed pull request, choose which one they use.

## State layout

Bucket `shiptrack-tfstate-<project number>` in the region, locked with the `gcs` backend's native
lock objects.

| Object | Owner |
|---|---|
| `gcp/bootstrap/default.tfstate` | bootstrap |
| `gcp/data/default.tfstate` | data |
| `gcp/cluster/default.tfstate` | cluster |
| `gcp/addons/default.tfstate` | addons |

## Recovery

- **A failure after "State is now stored remotely"**: re-run the workflow. State is in the bucket, so
  it picks up where it stopped.
- **The run failed while creating the bucket**: nothing is stored yet. If the bucket exists, import
  it from a workstation with credentials, or delete the empty bucket and re-run:
  `terraform import google_storage_bucket.state <bucket-name>` (then re-run the workflow).
- **A stuck lock on the bootstrap state** (`gcp/bootstrap/default.tflock` left behind by a cancelled
  run): delete that one object from the bucket after confirming no run is in progress.
