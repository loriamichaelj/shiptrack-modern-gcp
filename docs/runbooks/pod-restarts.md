# Pod restarts

**Use it** when `pod-restarts` fires: a container in the `shiptrack` namespace restarted more than three times in ten
minutes.

1. `kubectl -n shiptrack get pods`. The `RESTARTS` column names the container; the dashboard's restart tile shows when.
2. `kubectl -n shiptrack describe pod <pod>`: the last state says `OOMKilled` (memory), `Error` (the process
   exited), or a failing liveness probe.
3. `kubectl -n shiptrack logs <pod> --previous`: the end of the last run. The record before the exit is the cause.
4. Spot nodes are reclaimed from time to time and the pods on them restart once; that alone does not reach
   three. A repeating restart is a defect.
5. Fix forward with a new release ([deploy-and-rollback](deploy-and-rollback.md)), or roll back to the last digest
   that did not restart.

## Check
- No restarts for fifteen minutes and the alert clears.

**Tested:** not yet.
