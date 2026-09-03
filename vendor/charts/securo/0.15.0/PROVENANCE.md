# Provenance — securo chart 0.15.0

| | |
|---|---|
| Upstream | https://github.com/securo-finance/securo |
| Source | `charts/securo/` at tag **`v0.15.0`** |
| Retrieved | 2026-09-03, from the release tarball, not from `main` |
| Chart / appVersion | 0.15.0 / 0.15.0 |
| Licence | AGPL-3.0 — upstream `LICENSE` copied into this directory unmodified |
| Task | orchestrator OPS-31 / task 026 |

Upstream also publishes this chart as an OCI artifact at
`oci://ghcr.io/securo-finance/charts/securo`. It is vendored here anyway, for the
reason below.

## Why this is vendored rather than pulled

Upstream 0.15.0 exposes **no pod placement controls at all** — no `nodeSelector`,
`affinity`, `tolerations` or `topologySpreadConstraints`, in `values.yaml` or in
any template. Its own `values.yaml` states that the backend, celery worker and
MCP server mount the same attachment PVCs concurrently and that `ReadWriteOnce`
therefore only works if every consumer is on one node. cluster-apps has two
schedulable workers and no ReadWriteMany volume has ever been used on this fleet,
so without placement control the backend and worker can be scheduled apart and
one fails with a multi-attach error.

The alternative considered and rejected was enabling kustomize `--enable-helm` on
the ArgoCD repo-server so the chart could be inflated and patched in place. That
changes shared platform configuration for every application in the fleet in order
to fix one — a far larger blast radius than vendoring a single chart.

## Patches applied

Every patch is marked in-file with a `FLEET PATCH (task 026)` comment.

1. **Pod placement.** New `securo.placement` helper in `templates/_helpers.tpl`,
   rendering `global.placement.{nodeSelector,affinity,tolerations}`, included in
   all eight pod specs — backend, frontend, worker, beat, migration Job, MCP
   server, PostgreSQL and Redis.
2. **Explicit storage class on both StatefulSet claims.** Upstream's
   `volumeClaimTemplates` set no `storageClassName`, so the claim silently takes
   a cluster default. cluster-apps currently has *two* classes marked default
   (`local-path` and `longhorn`), so an unspecified claim could put the finance
   database on node-local storage. Now driven by
   `postgresql.persistence.storageClass` and `redis.persistence.storageClass`.
3. **PostgreSQL password from the Secret.** Upstream hardcodes the literal
   `POSTGRES_PASSWORD: postgres` in the StatefulSet, which cannot match a
   `DATABASE_URL` built from a real credential. Now a `secretKeyRef` into
   `global.existingSecret`, with a matching `secret.postgresPassword` default for
   the non-`existingSecret` path.
4. **PVC deletion protection.** `argocd.argoproj.io/sync-options:
   Prune=false,Delete=false` on the attachments PVC and both
   `volumeClaimTemplates`. `Prune=false` alone does not survive ArgoCD
   Application deletion.

Patches 1 and 3 are candidates to upstream; when they land, this vendor
directory should be dropped in favour of the OCI chart. Patch 2 is arguably an
upstream bug too.
