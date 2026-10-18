# State recovery

**Use it** when a Terraform state file was deleted, overwritten, or no longer matches reality. The state bucket
keeps the newest ten versions of every object, and nothing but the three pipeline accounts can write to it.

1. Actions, **ops-check-state** (read-only). It lists each root's saved versions: name, version number, time.
   Choose the last version from before the problem.
2. From your own machine, as the project owner, copy that version over the live object:

   ```sh
   gcloud storage cp "gs://<STATE_BUCKET>/gcp/<root>/default.tfstate#<VERSION>" \
     "gs://<STATE_BUCKET>/gcp/<root>/default.tfstate"
   ```

   `<root>` is `seed`, `data`, `cluster`, `addons`, or `finops`. The bucket is `shiptrack-tfstate-<PROJECT_NUMBER>`.
3. Open a pull request that touches the root so **ci-terraform** plans it. The plan should show only the changes
   you expect. If it shows resources as creates that exist, the version is too old: pick a newer one.
4. If nothing usable remains, import the resources one at a time with a pull request that adds `import` blocks,
   then plan until it shows no changes.

## Check
- The plan comment says "No changes" for the root.

**Tested:** not yet.
