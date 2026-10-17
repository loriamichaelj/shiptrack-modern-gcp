# network

The VPC, a subnet with secondary ranges for pods and services and Private Google Access, a router with
one Cloud NAT gateway, and the range and peering for private services access (ADR-0007). Flow logs are
off. Called by `terraform/data`.

Resources: `google_compute_network.this`, `google_compute_subnetwork.this`, `google_compute_router.this`,
`google_compute_router_nat.this`, `google_compute_global_address.private_services`, and
`google_service_networking_connection.private_services`. None takes labels.

Cost: Cloud NAT is about $4 to $6 a month with no traffic **[VERIFY]**; the rest is free. `destroy-network`
takes the whole module down.
