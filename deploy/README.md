# deploy

What `deploy-app` needs to put a release on the cluster. Nothing here names the project, a bucket, or a service account.

| Path | What it holds |
|---|---|
| `values-gcp.yaml` | Helm values for `cloud: gcp`: fixed replicas, Spot pods, the pool sizes, and the names of the topics, subscriptions, and secrets the data root creates |
| `chart-ref` | The commit of `shiptrack-modern` whose chart is deployed. Change it in a pull request to move to a newer chart |
| `gateway/` | The UI's load balancer: the Gateway, its route, the health check, the backend policy that attaches Cloud Armor, and the network policy that admits it. Applied and deleted by `ops-ui-port`, never by `deploy-app` |
| `db-init/` | The service account and the Job that create the application's database roles and schema, from the release's own image |

The image digest, the project, the proof-of-delivery bucket, and the signer's email are passed with `--set` by
`scripts/chart-args.sh`. `deploy-app` takes the project and the bucket from the `GCP_PROJECT_ID` and
`GCP_PROOF_OF_DELIVERY_BUCKET` secrets of the `dev` environment, and builds the signer's email from the project. The pull request checks render the chart with the same script and placeholder
values, validate it with kubeconform, scan it with checkov, and run `scripts/check-connection-budget.py`, which fails
if the pools could open more connections than the database allows.

## Deploying

Run **deploy-app** from `dev` with the image digest from `shiptrack-modern`'s `release-image` run (its job
summary and the `publish-ghcr` job show it), and approve the `dev` environment. It checks that the digest can
be pulled, runs the db-init Job, installs the chart with `--atomic`, waits for every Deployment, runs the
contract smoke suite through a port-forward, and rolls back to the previous revision if that fails. While Helm
waits, `scripts/sample-rollout.sh` prints the pods, events, and the log of any pod that is not ready, because
an atomic install removes them when it fails. `ops-contract` runs the full contract suite the same way. `ops-validate` runs the carrier simulator through a
port-forward while the pods are restarted or deleted, and checks that no accepted event was lost (`deploy`,
`preemption`), or runs `validation/sla-check.yaml` in the cluster to check one alert per breached shipment (`sla`).
