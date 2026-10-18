# Availability burn

**Use it** when `slo-availability-fast-burn` (SEV1: the 0.5% error budget burning over 14 times too fast, over 1 h and
5 min) or `slo-availability-slow-burn` (SEV2: over 6 times, over 6 h and 30 min) fires.

1. Dashboard `shiptrack`: the error ratio and request tiles show when it began and whether it still lasts.
2. Did a deploy just happen? Look at the last **deploy-app** run. If the errors began with it, roll back
   ([deploy-and-rollback](deploy-and-rollback.md)) first and look at the cause afterwards.
3. Otherwise, Cloud Logging: severity `ERROR`, namespace `shiptrack`, the api container. Find the
   failing route and its error. Database errors point at Cloud SQL; queue errors at Pub/Sub; one route points at the code.
4. Both api replicas on Spot nodes can be reclaimed together, which is a short outage the design accepts. If it
   repeats, set `spot: false` in `deploy/values-gcp.yaml` and deploy.

## Check
- The 5xx ratio is back near zero and the alert clears. Keep the dashboard open for the long window.

**Tested:** not yet. Both burn-rate alerts exist; no 5xx has been injected.
