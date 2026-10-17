# ui-ingress

What the browser URL needs from Google Cloud before the Gateway can create the load balancer: a subnet for the
regional load balancer's proxies, a reserved regional address, and a Cloud Armor policy that denies everyone and
admits one range. The Gateway, the route, and the policies that bind these to the service are in `deploy/gateway`
and are applied by `ops-ui-port`. The URL is `http://<the address>/ui/`: plain HTTP, with no certificate.

The allow rule holds an unroutable range until `ops-ui-port` opens it with the range in a masked secret, and puts it
back to close. Terraform ignores that range.

Cost: the load balancer's forwarding rule is about $18 a month, and Cloud Armor about $6 once the Gateway exists
**[VERIFY]**. The reserved address is free while the load balancer uses it. `destroy-ingress` removes these resources
after `ops-ui-port remove` has deleted the Gateway.
