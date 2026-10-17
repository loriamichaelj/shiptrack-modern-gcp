# gke-autopilot

The cluster `shiptrack` (ADR-0005, ADR-0007): Autopilot, private nodes behind Cloud NAT, the regular release
channel, Workload Identity, and managed Prometheus. The control plane has its DNS endpoint on and its IP
endpoint off, so IAM is the gate and there is no address to allow-list or leak. Nodes run as the account
`shiptrack-gke-node`. Cost allocation is on, so the billing export splits by namespace and label.

`deletion_protection` (default true) protects the cluster. Only `destroy-cluster` lowers it, inside its
approved run.

Cost: the management fee is covered by the free-tier credit for one cluster per billing account, and the Spot pods
the chart schedules are about $5 to $10 a month **[VERIFY]**. An idle Autopilot cluster has no node charge.
