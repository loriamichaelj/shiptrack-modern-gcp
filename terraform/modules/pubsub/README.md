# pubsub

Two flows. **events**: topic `shiptrack-carrier-events`, pull subscription
`shiptrack-carrier-events-worker` (ack deadline 60 s, retention 4 days). **notifications**: topic
`shiptrack-notifications` (retention 7 days), pull subscription `shiptrack-notifications-worker` filtered on the
`detail_type` attribute (`ShipmentDelivered` or `ShipmentException`).

Each subscription dead-letters to `<topic>-dead-letter` after 5 attempts, and each dead-letter topic has an
`-inspect` subscription (retention 14 days) for reading what failed. No subscription expires. Pub/Sub's service
agent is allowed to publish to the dead-letter topics and to acknowledge on the source subscriptions.

The names match the chart's GCP values. The workloads' own access is granted with the cluster.

Cost: the first 10 GiB a month are free, so this is about nothing at this size **[VERIFY]**.
`destroy-pubsub` deletes the topics and subscriptions and any messages in them.
