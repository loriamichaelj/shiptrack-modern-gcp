# deploy/gateway

The Kubernetes objects of the UI's load balancer, applied by the `ops-ui-port` workflow (`open`) and deleted by
it (`remove`). They are not part of `deploy-app`, so a deploy never starts the load balancer's charge.

| File | What it is |
|---|---|
| `networkpolicy.yaml` | Admits the load balancer's proxies and Google's health checkers to the api's port |
| `backend-policy.yaml` | Attaches the Cloud Armor policy to the api's backend |
| `health-check.yaml` | Makes the load balancer check `/readyz` |
| `gateway.yaml` | The regional external Application Load Balancer, HTTP on port 80, on the reserved address |
| `route.yaml` | Sends everything to the api service |

The policies are applied first and the Gateway last, so the load balancer never serves without the Cloud Armor
policy. The address and the policy come from `terraform/modules/ui-ingress`.
