# Deploy and rollback

**Use it** to put a release on the cluster, or to put the previous one back.

## Deploy
1. In `shiptrack-modern`, find the release's image digest: the `publish-ghcr` job of its `release-image` run.
2. Actions, **deploy-app**, branch `dev`, paste the digest (`sha256:<64 hex>`), approve the `dev` environment.
3. The run checks the digest can be pulled, runs the `db-init` Job, installs the chart with `--atomic`, waits for every
   Deployment, and runs the contract smoke suite. If the smoke suite fails it rolls the release back by itself.
4. The job summary records the digest and the Helm revision. Keep the line: it is the way back.

## Roll back
A schema change is not undone by a rollback, so a release must keep the schema compatible with the one before it.
1. Take the previous digest from the last good run's summary.
2. Run **deploy-app** with that digest. It is the same procedure, so the checks and the smoke suite run again.
3. If a deploy is stuck, **deploy-app** has already rolled back; read its log, which includes the pod events the
   sampler printed while Helm waited.

## Check
- The run is green and `ops-contract` passes.
- The dashboard `shiptrack` shows requests and no 5xx; no alert is firing.

**Tested:** the deploy path on 2026-10-17 and 2026-10-18 (`deploy-app` runs 39072240811 and 39141714025: image check,
`db-init`, Helm `--atomic`, rollout, smoke suite). Not covered: a rollback to an older digest, and the automatic rollback
after a failed smoke suite, because only one image has been deployed.
