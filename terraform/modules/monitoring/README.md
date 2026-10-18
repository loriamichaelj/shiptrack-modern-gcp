# monitoring

The alert policies, the notification channel, the log-based heartbeat metric, and the dashboard for the
workloads (ADR-0014, ADR-0032). Called by the `data` root. There are no pods: everything is Cloud Monitoring.

| Alert | Reads | Severity |
|---|---|---|
| `events-queue-age` | oldest unacknowledged message on the events subscription above 120 s for 5 min | SEV2 |
| `events-queue-age-critical` | the same above 600 s | SEV1 |
| `events-dlq-visible`, `notify-dlq-visible` | any message on a dead-letter subscription | SEV2 |
| `pod-restarts` | more than 3 container restarts in 10 min in the `shiptrack` namespace | SEV2 |
| `sla-scan-heartbeat` | no `sla_scan_completed` log record for 15 min | SEV2 |
| `slo-availability-fast-burn` | error budget burning 14.4 times too fast over 1 h and 5 min | SEV1 |
| `slo-availability-slow-burn` | 6 times too fast over 6 h and 30 min | SEV2 |

Each alert's documentation names a runbook under `docs/runbooks/`. `destroy-monitoring` removes the module.

Inputs: the project, the alert address (a masked secret), labels, and the subscription names from the
`pubsub` module. Outputs: the channel ID and the alert names.
