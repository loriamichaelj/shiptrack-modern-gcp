# terraform/finops

Cost control for the project (ADR-0028). It is its own root so that taking the `data` groups down does not
remove the budget or the cost history, and no `destroy-` workflow removes it.

| File | Holds |
|---|---|
| `budget.tf` | A $50 monthly budget on the project that alerts at 50%, 90%, and 100% of actual spend and at 100% of forecast, to an email channel and to the billing account's default recipients. It never stops anything |
| `cost_export.tf` | The BigQuery dataset the standard usage cost export writes to, and read access to it for the plan account |

## Inputs

`billing_account_id` and `alert_email` are secrets (`GCP_BILLING_ACCOUNT_ID` and `GCP_ALERT_EMAIL` in the `ci`
and `dev` environments), marked sensitive, and masked by `terraform-ci.sh`. The email address is stored in the
state bucket as a channel label, which only the three pipeline accounts can read.

## Running it

1. Grant the two billing account roles by hand (`terraform/seed/README.md`, "Billing").
2. A pull request that changes this root runs **ci-terraform**, which plans it as `shiptrack-plan`.
3. After the merge, Actions, **apply-terraform**, root `finops`, on `dev`.
4. Switch on the standard usage cost export in the billing console, pointing at the dataset
   `shiptrack_billing_export`. Terraform cannot do this step **[VERIFY]**.
5. **check-cost** (Actions, on `dev`, approve the `ci` environment) prints the month's cost by service, by
   the `name` label, and by day, against the budget. The export fills within a day of being switched on.

The budget is free. BigQuery storage for one project's cost rows is far under the free tier **[VERIFY]**.
