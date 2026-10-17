# deploy

What `deploy-app` needs to put a release on the cluster. Nothing here names the project, a bucket, or a service account.

| Path | What it holds |
|---|---|
| `values-gcp.yaml` | Helm values for `cloud: gcp`: fixed replicas, Spot pods, the pool sizes, and the names of the topics, subscriptions, and secrets the data root creates |
| `chart-ref` | The commit of `shiptrack-modern` whose chart is deployed. Change it in a pull request to move to a newer chart |
| `db-init/` | The service account and the Job that create the application's database roles and schema, from the release's own image |

The image digest, the project, the proof-of-delivery bucket, and the signer's email are passed with `--set` from masked
secrets by `scripts/chart-args.sh`. The pull request checks render the chart with the same script and placeholder
values, validate it with kubeconform, scan it with checkov, and run `scripts/check-connection-budget.py`, which fails
if the pools could open more connections than the database allows.
