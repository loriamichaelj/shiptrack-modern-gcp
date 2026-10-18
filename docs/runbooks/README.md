# Runbooks

One page per situation. Each says when to use it, what to check, what to do, and how to know it worked. A
runbook is tested once, on the running stack, and its last line records when and how. Commands that need the
cluster assume you fetched credentials yourself:

```sh
gcloud container clusters get-credentials shiptrack --region us-central1 --project <PROJECT_ID> --dns-endpoint
```

Nothing here changes the stack except through a workflow, and nothing prints a secret.

| Runbook | Use it when |
|---|---|
| [deploy-and-rollback](deploy-and-rollback.md) | You put a release on the cluster, or put the previous one back |
| [dead-letter-redrive](dead-letter-redrive.md) | A dead-letter alert fired |
| [secret-rotation](secret-rotation.md) | The database passwords change |
| [state-recovery](state-recovery.md) | A Terraform state file is lost or wrong |
| [event-backlog](event-backlog.md) | `events-queue-age` or `events-queue-age-critical` fired |
| [pod-restarts](pod-restarts.md) | `pod-restarts` fired |
| [sla-scan-stopped](sla-scan-stopped.md) | `sla-scan-heartbeat` fired |
| [availability-burn](availability-burn.md) | `slo-availability-fast-burn` or `slo-availability-slow-burn` fired |
