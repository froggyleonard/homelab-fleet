# Sequential recovery rehearsal

I restore and validate one isolated scratch volume at a time. I retain two
replicas, the existing storage reservations, all production volumes and every
remote recovery point. The private recovery checklist holds source identities,
credential custody, content baselines, receipts and concrete authorizations.

The dedicated `ops45-restore` AppProject and manual child Application live under
`clusters/infra/apps/`. The root discovers their registration after an authorized
merge. The child points at the reviewed `00-idle` stage;
it has no automated sync and no deletion finalizer. An idle sync creates only
the protected scratch namespace, deny-all policy and stage ResourceQuota.

## Stage paths and entry gates

All paths below are relative to `clusters/apps/rehearsals/ops45/`.

| Stage | Storage path | Consumer path | Capacity per worker |
| --- | --- | --- | --- |
| File recovery | `10-mealie/00-storage` | `10-mealie/01-inspect` | 5 GiB |
| PostgreSQL 18 | `20-tempo/00-storage` | `20-tempo/01-inspect` | 5 GiB |
| PostgreSQL 16 | `30-moneymatter/00-storage` | `30-moneymatter/01-inspect` | 5 GiB |

The [machine-readable inventory](ops45-rehearsal-stages.json) is the exact
resource-name contract. Each storage path includes the idle resources and one
Longhorn Volume, static Retain PV and prebound PVC. Each consumer path adds one
pod. The namespace quota permits one PVC, 5 GiB of requests and one pod. It is
an extra admission check, not a guarantee that old Longhorn Volume CRs have
been deleted: those objects live in `longhorn-system` outside this quota.

Before each stage, require the previous stage's pod, PVC, PV and Longhorn Volume
to be absent, its replicas removed and its allocation released. Check exact live
UIDs, PV handles, namespace labels and the Application resource inventory against
the private receipts. Refuse collisions, unknown resources or a partial cleanup;
never proceed merely because a PVC is absent. Recheck both workers' scheduled
allocation after reservations/overprovisioning, filesystem free space, node
pressure, backup activity and target availability. The table excludes temporary,
snapshot, engine and cache overhead. No workload tolerates a reduced replica count
to make this rehearsal fit.

The file Volume's `fromBackup` is bound to a verified completed backup URL.
Before each new rehearsal, refresh that exact source in a reviewed GitOps change; the private preflight must reject the marker, an empty value, a changed
source identity or an unresolved URL. Never replace it with an empty string: that
would create an empty volume instead of restoring files. Record the immutable
source and Git revision privately, without putting source identifiers in this
runbook or PR text. The database volumes intentionally start empty and receive
verified off-site dump/globals pairs through the bounded private recovery client.

## Execute and inspect

1. Satisfy source, independent recovery access, capacity and collision checks.
   Review the exact immutable revision and authorize the concrete stage sync.
   Change the child's source path through Git, retain manual sync, and inspect
   the rendered diff before synchronizing that revision.
2. Sync only the selected `00-storage` path. For file recovery, require completed
   restore with no engine errors, `restoreRequired=false` and a detached volume
   before attaching the inspector. For all stages require the exact PV/PVC
   bindings and no ongoing recovery failure. An empty database volume is only
   storage preparation; its replicas may initialize only after attachment.
3. Switch through a reviewed change to that stage's `01-inspect` path, then sync
   its exact revision. Require two healthy replicas and verify effective
   isolation and bindings before sending any database input. Restore globals
   before the matching custom archive; use
   the distinct `ops45_admin` bootstrap role and reject conflicts or prior data.
   Suppress SQL diagnostics, retain sanitized receipts, and never retry a partial import.
4. Validate file content against the selected backup's baseline, or database
   schema, representative contents, roles, grants and original-credential login.
   A process exit, successful dump or archive listing alone is insufficient.
   Record stage identity, elapsed recovery time, checks and remaining limitations
   before any cleanup. Start no application server, worker or integration.

The namespace has no network allows, Service, ingress, integration credentials
or mounted API token. PostgreSQL listens only on its Unix socket. Only the
distinct bootstrap role uses local trust; restored application roles require
SCRAM password authentication. The authorized recovery client exercises the
original password without exposing it to argv, pod logs or model output.
Database server stdout/stderr are suppressed because failing globals statements
can contain password hashes; private sanitized receipts own diagnostics.

Each pod expires after 24 hours, uses `restartPolicy: Never`, runs without root,
drops capabilities and has a read-only root filesystem. The database program refuses any pre-existing PG_VERSION. A Downward API UID
binds each recovery exec to its inspected pod, and an exclusive data-directory
attempt marker prevents replay after an interrupted import. A failed or expired
pod requires a new reviewed stage with fresh scratch storage. Database requests are
100m CPU/256Mi and limits 1 CPU/1Gi; temporary storage is limited to 128Mi. The
file inspector requests 25m/32Mi and limits 100m/128Mi, mounts only the restored
scratch PVC read-only and does not apply fsGroup ownership changes.

The engine remains Longhorn 1.12.0 to match the current storage runtime. The
PostgreSQL 18.6/16.15 digests preserve the source runtime selected for the earlier
rehearsal; this preparation does not upgrade production. Verify current source
major/digest compatibility and upstream availability before execution.

## Stop, preserve and clean up

To stop consumers, switch back to the **same stage's** `00-storage` path and
perform the authorized pod prune while retaining the child Application. Observe
the pod's deletion, volume detach and inactive engine restore before continuing.
Reverting to another stage or deleting the Application can leave storage behind.

Namespace, PVC, PV and Longhorn Volume have `Prune=false,Delete=false`; every PV
also has reclaim policy Retain. These remain in force throughout execution.
Switching to idle intentionally cannot clean up protected storage. A manifest
revert preserves the rehearsal and is not evidence of released capacity.

After accepting and recording results, prepare a **separate, specifically
authorized cleanup change for the current stage only**. Check its exact live
UIDs/handles and absence of consumers/attachments against the saved evidence.
Use named patches for that stage's PVC, PV and Volume to remove only `Prune=false`,
retaining `Delete=false` and PV Retain. Sync and verify those exact annotation
changes before removing resources from the desired graph. Do not use a broad
kind/label selector, global prune override or namespace deletion as a shortcut.

Prune the scratch claim first while retaining its PV and Volume; observe claim
deletion. Then prune its Retain PV; observe deletion and verify no claim or
attachment remains. Finally prune only its named Longhorn Volume and observe its
replicas disappear. The Mealie overlays `02-release-prune`, `03-remove-pvc`, `04-remove-pv` and
`05-remove-volume` encode these individual steps. Do not skip a readback gate
or combine their deletion stages into one sync. Keep the Application,
namespace, policy and quota registered throughout. Return the child to `00-idle`
only after the current storage inventory is empty and capacity is released.
Stop if a finalizer or pruning error prevents progress; do not force deletion.

After the last stage, namespace cleanup is another reviewed operation. Confirm
it contains no unexpected data, release only its own prune protection, and prune
it while the Application remains registered. Remove the child and AppProject
only after observing the empty Application inventory and absent namespace. Never
unregister before pruning: this child has no cascading deletion finalizer.

Cleanup discards only that rehearsal state; repeating it requires a new approved
restore from the retained backup. Rollback before cleanup stops consumers and
preserves scratch data. Rollback after deletion cannot reconstruct it from Git.
No source PVC, database, scheduled backup, remote object, credential or production
application is part of this cleanup.

See [Longhorn restore](https://longhorn.io/docs/1.12.0/snapshots-and-backups/backup-and-restore/restore-from-a-backup/)
and the [backup architecture](../adr/0008-backup-architecture.md).
