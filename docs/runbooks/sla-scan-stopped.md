# SLA scan stopped

**Use it** when `sla-scan-heartbeat` fires: no `sla_scan_completed` record for fifteen minutes. The scan is a CronJob that
runs every five minutes and flags overdue shipments, so overdue shipments are not being flagged.

1. `kubectl -n shiptrack get cronjob shiptrack-sla-scan`. `SUSPEND` should be `False`, and `LAST SCHEDULE` recent.
2. `kubectl -n shiptrack get jobs -l app.kubernetes.io/component=sla-scan`. Failed jobs: read one's log
   (`kubectl logs job/<name>`); `sla_scan_failed` names the error, usually the database.
3. A job that never starts: describe it. Spot capacity can delay a pod for a few minutes.
4. A suspended CronJob was set by the release's values (`slaScan.suspend`). Deploy a release that clears it.
5. Once it runs again the alert clears; shipments that went overdue meanwhile are flagged by the next scan, once each.

## Check
- A `sla_scan_completed` record in Cloud Logging, and `ops-validate` `sla` passes.

**Tested:** not yet.
