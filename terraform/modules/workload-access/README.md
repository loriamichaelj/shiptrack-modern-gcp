# workload-access

One workload's IAM bindings. The workload is a Kubernetes service account in the project's
workload identity pool, so it holds no key and no Google service account. Each role is granted on the single
resource the workload uses: `pubsub.publisher` on a topic, `pubsub.subscriber` on a subscription,
`secretmanager.secretAccessor` on a secret, `storage.objectUser` on the bucket, and
`iam.serviceAccountTokenCreator` on the proof-of-delivery signer.

The pool exists once the cluster does, so the `cluster` root calls this after the cluster. Topics,
subscriptions, and secrets are sets of names; the bucket is a flag and a value, because its name is not
known until the bucket exists.
