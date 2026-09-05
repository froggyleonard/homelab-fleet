# Sure retirement after MoneyMatter workflow cutover

I am preparing Sure retirement as Talos preflight. This change remains a draft
until the separate MoneyMatter workflow migration has completed its live
cutover checks and I explicitly approve this merge.

## Dependency and effect

FIN Poller, FIN Daily Coach and FIN Weekly Coach currently have published
graphs calling Sure. The migration task owns their port to MoneyMatter. Before
merging, verify the **published** graphs and natural scheduled runs, including
any subworkflows and indirect credential/URL references. Preserve the old
published versions for rollback. Do not disable or edit these workflows here.
Keep OPS Backup Alerts working. The old Daily Financial Driver is already
inactive; confirm it stays inactive and is not republished against Sure.

ArgoCD prunes Sure's web, worker and Redis Deployments, both Services and its
IngressRoute. Both public and internal Sure entry points lose their backend.
Redis uses emptyDir with persistence disabled; pending queue/cache state is
lost. Verify the worker has no required work pending before approval.

The Application stays present to perform pruning. Namespace, policies and
SOPS-managed secrets remain. Sure has no PVC in the live baseline; its database
and role remain in shared PostgreSQL alongside retained tenants. This first
stage does not remove database data, credentials, DNS, tunnel or SSO objects.

## Pre-merge checks

1. Obtain the migration task's successful cutover evidence and verify there
   are no remaining active Sure callers. Recheck n8n inventory immediately
   before approval; saved draft edits alone do not satisfy this gate.
2. Preserve a current full shared-PostgreSQL dump outside rotation, validate
   gzip/trailer, and record recovery location privately. `pg_dumpall` includes
   globals. The checked 2026-09-05 04:00 archive passed gzip validation; an
   independent restore remains unproved. Do not claim that bank re-sync can
   recover manual categories, attachments or configuration.
3. Recheck web/worker local uploads before removing their pods and preserve
   any irreplaceable files. The inspected web pod had no volume mounts and
   `/rails/storage` held only a zero-byte `.keep` file. Resolve pending
   background work explicitly; the pod-local check is not a DB attachment audit.
4. Record exact PR revision, rollout window and explicit merge approval.
   After pruning, confirm no Sure workload or ingress remains, the retained
   DB is intact and MoneyMatter workflows continue on natural schedules.
   Capture a final Sure database/globals archive after writers stop.

## Rollback and final cleanup

Revert this specific commit through GitOps. Retained database and encrypted
secrets allow the original app version to return; Redis starts with an empty
queue. Restore original published finance workflow versions only after Sure
is healthy and coordinate that reversal with the migration task. If writes
have continued in MoneyMatter, account for them before reversing any data
cutover. For database recovery, restore globals before the database into an
isolated instance and validate app access.

After retention and recovery acceptance, prepare shared tenant-init/network
allow cleanup, separately authorized database/role removal, namespace resource
pruning followed by Application/AppProject cleanup, Cloudflare hostname/Unbound
records, Authentik application/provider, Homarr links and seat MCP removal.
Credential retirement and SOPS edits stay user-operated. Do not remove shared
PostgreSQL or its backups while other tenants remain.
