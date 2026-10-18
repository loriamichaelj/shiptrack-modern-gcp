# Dead-letter redrive

**Use it** when `events-dlq-visible` or `notify-dlq-visible` fires. A message failed five deliveries and waits in the
dead-letter queue. Messages are kept for 14 days there.

## Find out why
1. Actions, **ops-queues**, action `status`, the flow that alerted. It prints the count and each message's id,
   age, and delivery attempts, never a body.
2. Read the worker's log around the message's publish time in Cloud Logging
   (`resource.type="k8s_container"`, namespace `shiptrack`, severity `ERROR`). The record names the error and
   the message's `idempotency_key`.
3. Decide: a bug in the application (fix and deploy first), a failing dependency (wait until it is back), or a
   message that is wrong and should not be applied (run `discard`, or leave it; it expires after 14 days).

## Redrive
Only after the cause is fixed, or the message returns here after five more deliveries.
1. Actions, **ops-queues**, action `redrive`, the same flow. Approve the `dev` environment.
2. Each message is republished to the flow's topic and acknowledged in the dead-letter queue only after the
   publish worked. The run prints how many it moved. A message that fails again comes back to the dead-letter
   queue within seconds; the run sees that, leaves it there, and stops with a note, so run `discard` for it.
3. Run `status` again: it should show 0 messages.

## Check
- The alert clears within a few minutes.
- The shipment's tracking timeline shows the event (an event applied twice is harmless: the idempotency key
  makes the second a no-op).

**Tested:** 2026-10-18, on the events queue, with `ops-queues`. `poison` published a malformed message; `status` showed it in
the dead-letter queue; `redrive` moved it back, saw it fail again and return, and stopped; `discard` dropped it; `status`
showed 0. The test found two defects in the first version of `redrive` (it looped on a message that still fails), both
fixed. Not covered: redriving a message that then succeeds after a fix, the notifications flow, and the alert email,
which only the person who receives it can confirm.
