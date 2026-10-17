# proof-of-delivery-storage

The proof-of-delivery bucket `shiptrack-proof-of-delivery-<random suffix>` (ADR-0011, ADR-0023): Standard class,
uniform access, public access prevention enforced, versioning off. The service account
`shiptrack-proof-of-delivery`, which signs the download URLs, may read objects and nothing else.

`protection` (default true) keeps a bucket that holds objects from being destroyed. Only
`destroy-proof-of-delivery-storage` lowers it, inside its approved run.

Cost: the first 5 GiB in `us-central1` are free **[VERIFY]**.
