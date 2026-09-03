# Runbook — re-vendoring the Securo chart

The Securo Helm chart is vendored at `vendor/charts/securo/<version>/` because
upstream exposes no pod placement controls. See the `PROVENANCE.md` in that
directory for why, and for the full patch list.

**Renovate reports upstream Securo releases on the dependency dashboard; it does
not and cannot update vendored files.** Acting on a reported bump means running
this procedure.

## When

A Securo release appears on the dependency dashboard (the backend/frontend image
rules are `dependencyDashboardApproval`, so no PR is raised automatically). The
chart version, `appVersion` and both image tags move together upstream.

## Procedure

1. Fetch the new chart from the release **tag**, never from `main`:

   ```bash
   V=<new version>
   TMP=$(mktemp -d)
   curl -sSL "https://codeload.github.com/securo-finance/securo/tar.gz/refs/tags/v$V" -o "$TMP/s.tgz"
   tar -xzf "$TMP/s.tgz" -C "$TMP"
   mkdir -p vendor/charts/securo/$V
   cp -a "$TMP/securo-$V/charts/securo/." vendor/charts/securo/$V/
   cp "$TMP/securo-$V/LICENSE" vendor/charts/securo/$V/LICENSE
   ```

2. Diff the new upstream chart against the previous vendored version to see what
   changed underneath the patches:

   ```bash
   diff -ru vendor/charts/securo/<old>/templates vendor/charts/securo/$V/templates
   ```

3. Re-apply the four patches. Each is marked in the old copy with a
   `FLEET PATCH (task 026)` comment — `grep -rn 'FLEET PATCH' vendor/charts/securo/<old>/`
   lists every site. **Check first whether upstream has adopted any of them**; if
   upstream now ships `nodeSelector` and a Secret-sourced PostgreSQL password,
   drop the vendor entirely and move the Application to
   `oci://ghcr.io/securo-finance/charts/securo`.

4. Copy `PROVENANCE.md` forward and update its version, retrieval date and patch
   list.

5. Render and assert before committing — this is the gate, not a formality:

   ```bash
   helm template securo vendor/charts/securo/$V -n securo -f /tmp/securo-values.yaml > /tmp/rendered.yaml
   ```

   Assert on the rendered output that: every PVC and `volumeClaimTemplate` has
   `storageClassName: longhorn` **and** the `Prune=false,Delete=false` sync
   option; every pod spec carries the `nodeSelector`; no image tag ends in
   `:latest`; no `Ingress` is rendered; `POSTGRES_PASSWORD` comes from a
   `secretKeyRef` and not a literal.

6. Point `clusters/infra/apps/securo.yaml` at the new path, update both image
   tags, and update the `vendor/charts/securo/<old>` removal in the same commit.

7. Merging deploys immediately. A chart bump crossing a database migration is not
   reversible by reverting the commit — take a backup first and read the upstream
   release notes for migration steps.

## What this runbook does not cover

Rolling Securo back. That is in the task 026 plan: stage 1 removes only the chart
Application and preserves the namespace, Secret and every PVC; stage 2, namespace
and PVC deletion, is a separately approved retirement step after a verified dump.
A blanket `git revert` is not a rollback — it prunes the config Application that
owns the namespace and cascades the volumes.
