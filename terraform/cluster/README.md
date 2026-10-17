# terraform/cluster

The GKE Autopilot cluster and the workloads' IAM bindings. Design: `docs/DESIGN.md` §8.3.

| File | Holds |
|---|---|
| `main.tf` | Reads the `data` root's outputs from its state, calls `gke-autopilot` for the cluster, and calls `workload-access` once per workload |
| `locals.tf` | What each workload may use (design §7.3) |
| `outputs.tf` | The cluster's name. Its endpoint is deliberately not an output |

## Running it

Apply the `data` root first: this root reads its state.

- A pull request that changes this root runs **ci-terraform**, which plans it as `shiptrack-plan`.
- After the merge, Actions, **apply-terraform**, root `cluster`, on `dev`. Approve the `dev` environment. Creating
  the cluster takes about 10 to 15 minutes.
- **ops-check-cluster** then proves the deploy account can reach the control plane through the DNS endpoint.
- **destroy-cluster** takes the cluster and the bindings down again, after two approvals and the typed name `cluster`.
  Remove the add-ons first.

The cluster is the first thing here that can cost real money: the management fee is covered by the free-tier credit,
and Spot pods are billed only while pods run **[VERIFY]**. State is `gcp/cluster/default.tfstate`.
