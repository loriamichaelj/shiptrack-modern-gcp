# Event backlog

**Use it** when `events-queue-age` (SEV2, the oldest event has waited over 120 s) or `events-queue-age-critical`
(SEV1, over 600 s) fires. Events are accepted but not yet applied, so tracking shows old data.

1. Dashboard `shiptrack`: the queue age and depth tiles show how long it has lasted. Messages that keep
   failing go to the dead-letter queue after five tries; if `events-dlq-visible` is also firing, use
   [dead-letter-redrive](dead-letter-redrive.md).
2. `kubectl -n shiptrack get pods -l app.kubernetes.io/component=worker-events`. No Ready pod: look at the
   pod's events (`kubectl describe`), often a Spot pod waiting for capacity, which clears on its own in a few
   minutes.
3. A Ready pod and a growing queue: the worker is slow or stuck. Look at the worker's log for errors and at the
   database connections tile. If Cloud SQL is the bottleneck, check its CPU in the console.
4. `kubectl -n shiptrack rollout restart deployment/shiptrack-worker-events` is safe: a message that was being
   applied is redelivered and applied once.

## Check
- The queue age falls below 120 s and the alert clears.

**Tested:** not yet.
