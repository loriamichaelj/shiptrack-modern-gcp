# Teardown

**Use it** to stop the spend: everything that costs money goes, and what the pipeline needs to rebuild stays.

**Deleted:** the database and its backups, every proof-of-delivery document, every queued message, the cluster and what runs
in it, the network, the UI's load balancer, subnet, address, and policy, the secrets, and the monitoring. **Kept:** the seed
root (state bucket, service accounts, trust), the finops root (budget, billing export), and what you made by hand.

## Before
1. Stop traffic and note anything you want from the stack: `ops-queues status`, and the digest in the last `deploy-app` summary.
2. Check that no `deploy-app`, `ops-validate`, `ops-ui-port`, or `apply-terraform` run is in progress.

## Do it
1. Actions, **destroy-all**, branch `dev`, type `all`.
2. Approve the `dev` environment for the plan job. Read its summary: it lists the addresses and actions of the add-ons, the
   cluster, and the data root. Everything should be a delete.
3. Approve the `dev` environment for the destroy job. It deletes the Gateway, waits for the load balancer to go, destroys
   the add-ons, waits for the network endpoint groups to go, then destroys the cluster and the data root. Plan about 30 to 60 minutes; Cloud SQL and the private services
   connection are the slow parts.
4. If it fails, read the log and dispatch it again. What is gone is skipped and the rest is planned afresh.
   - "The load balancer is still there": nothing else was touched. Run **ops-ui-port** with `status`, then `remove`, and again.
   - "The network endpoint groups are still there": the add-ons are gone and the cluster is not. The cluster's controller
     removes them; list them with `gcloud compute network-endpoint-groups list`, wait, and dispatch again.
   - The network or the private services connection fails after three attempts: Google still holds the connection. Wait and dispatch again.
   - A resource is left in the project that Terraform did not make (a firewall rule, an endpoint group) and blocks the
     network: list it with `gcloud compute ... list`, and ask for it to be removed; the apply account will not be given more rights for it.

## Check
- Actions, **ops-check-cost** shows the cost falling over the next days; the billing export keeps the history.
- Console or read-only `gcloud` lists no cluster, no Cloud SQL instance, no forwarding rule, and no address in the project.
- A second **destroy-all** plan says "Nothing to change." for the data root.

## Bring it back
`apply-terraform` for `data`, `cluster`, then `addons`, then `deploy-app` with a digest. The Cloud SQL name, the bucket name,
and the passwords are new. Run `scripts/ui-access.sh open` for the new address.

**Tested:** not run. The script's paths (whole root, several protections, retry) were run against a stub of `terraform`, and
nothing was run against Google. The first run also tests the apply account's delete rights and the release of the private
services connection.
