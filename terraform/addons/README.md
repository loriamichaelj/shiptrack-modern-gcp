# terraform/addons

The `shiptrack` namespace and what the deploy account may do in it. Design: `docs/DESIGN.md` §8.4.

| File | Holds |
|---|---|
| `main.tf` | The namespace with the Pod Security `restricted` profile enforced and warned on, and a `Role` and `RoleBinding` that give `shiptrack-deploy` the workload kinds, `Job` and `CronJob`, network policies, `PodMonitoring`, Helm's release Secrets, read access to pods and events, and `pods/portforward`, in that namespace only |
| `locals.tf` | The labels and the deploy account's Kubernetes user name, which is its email |

GKE gives the deploy account nothing in the cluster through IAM beyond fetching credentials, so the role is
everything it can do. There is no Gateway: it is not built (ADR-0013).

## Running it

Apply the `cluster` root first.

- A pull request that changes this root runs **ci-terraform**, which plans it as `shiptrack-plan` with
  `-refresh=false`: refreshing Kubernetes objects needs RBAC the plan account does not have.
- After the merge, Actions, **apply-terraform**, root `addons`, on `dev`. The apply account reaches the cluster
  through its DNS endpoint with a short-lived token.
- **ops-check-cluster** then reports what the deploy account may do: list pods in `shiptrack` (yes), and in
  `kube-system`, in all namespaces, or nodes (no).
- **destroy-addons** takes the namespace and the role down, and everything running in the namespace with
  them, after two approvals and the typed name `addons`.

Cost: nothing. State is `gcp/addons/default.tfstate`.
