# OPS-2: n8n dedicated PostgreSQL migration

I migrate n8n's existing PostgreSQL database to its own PostgreSQL instance while
preserving the application version, credentials, published workflow versions,
execution history, data tables and the existing application PVC. The shared
source database and role remain available for recovery throughout acceptance
and the parent issue's observation period.

## Initial activation

This first stage keeps the n8n Deployment at one replica, using its existing
`postgres.postgres.svc.cluster.local` database host. Its container, environment,
Secret references, service, ingress route and application volume remain unchanged.
I add explicit `Prune=false,Delete=false` retention to the existing `n8n-data`
claim before introducing the dedicated database.

The new `n8n-postgres` StatefulSet has one replica and uses the reviewed
PostgreSQL 18.6-trixie image digest already used by the dedicated Authentik
database. I verified the [PostgreSQL 18.6 release](https://www.postgresql.org/docs/release/18.6/)
and image pin when preparing this stage. It mounts the explicit
`/var/lib/postgresql/18/docker` data directory, starts with only the `postgres`
bootstrap role/database, uses UTF-8 with `en_US.utf8`, and requires SCRAM for host
connections. I keep this target fresh while rehearsing in a disposable local
PostgreSQL instance. The final frozen capture is imported once into this target.

The dedicated `n8n-postgres-admin/password` Secret must be provisioned through
the constrained credential helper and committed as
`02b-postgres-admin.sops.yaml` before activation. KSOPS renders both that new
ciphertext and the unchanged existing `02-secrets.sops.yaml`. I do not replace the
application encryption key or its existing database password.

The StatefulSet's `data` claim template creates `data-n8n-postgres-0`. It and the
separate `n8n-pg-backups` claim request explicit 5 GiB Longhorn RWO storage with
retention annotations. The StatefulSet retains claims on deletion and scale-down.
I verify actual claim/PV/Longhorn identities and two healthy RW replicas on
separate workers after attachment. Desired replica counts alone are insufficient.

The namespace default-deny remains in place. I narrow the existing `n8n-egress`
policy from all pods to `app.kubernetes.io/name: n8n`, preserving its existing
application destinations. This prevents the new database and backup components
from inheriting application access to external services. The database has no
allowed ingress or egress during activation. Backup pods have only DNS and
same-namespace dedicated-DB egress; database ingress still blocks that connection
until a separate capture gate is reviewed. Services expose the target only within
the cluster. The complete namespace policy union and any Cilium overrides are
checked against the actual labels before accepting isolation.

The `n8n-pg-backup` CronJob is suspended. Its proposed schedule is 03:35 UTC, after
the existing dedicated Authentik backup and before the seat's daily export. It
uses the already validated dump/globals publication payload, runs as UID/GID 999,
validates a complete pair and atomically publishes a manifest-bearing generation.
The backup PVC alone does not provide independent disaster recovery. This stage
creates no one-shot backup Job or reader and does not import data or switch n8n.

## Baseline and final recovery gates

I retain private evidence containing source/target identities, application image
and runtime database settings, the existing encryption-key fingerprint, Secret
metadata, application PVC identity, full schema, table/sequence checks and
workflow publication bindings. I compare the complete database, including
archived workflows, credentials and sharing, users, data tables, settings,
execution history and migrations. MCP workflow listings may omit archived
workflows, and new-version publication tables can legitimately be empty.

Published workflow versions are separate from saved drafts. I preserve each
existing `versionId`, `activeVersionId`, active flag and historical definition,
including any intentional difference between draft and publication. I do not
re-publish workflows or use workflow import/export as a substitute for the full
native database migration. n8n's [publication documentation](https://docs.n8n.io/build/understand-workflows/save-and-publish-workflows)
explains why changing a saved draft can differ from changing the version used
by schedules and production webhooks.

I inspect both database-backed binary data and the existing application user
folder. No binary rows or files at one observation does not justify deleting or
replacing the PVC. I preserve that volume, encryption key and configuration
through the database move and retain its verified recovery coverage. I inspect
custom node/package state without exporting credential values. The n8n image
remains unchanged so application upgrades do not introduce database migrations
or workflow behavior changes during this operation.

Before freezing, I record active/waiting executions and natural workflow schedules
with their effective time zones. I drain running work and account for waiting
executions and incoming webhooks. The freeze is a GitOps scale to zero of the
single n8n Deployment; I verify the pod is gone and the source database has no
application sessions. I do not alter workflow publication state to simulate a
freeze. I record the outage and missed-trigger boundary explicitly.

I retain a final complete source dump and globals set outside normal rotation.
I prove a globals-first restore in an isolated PostgreSQL instance, preserving
role attributes, existing password verification, every table, sequences and
publication bindings. The dedicated target administrator remains distinct and
unchanged. After the final single target import, I verify those same acceptance
bindings while application writers are still stopped.

The [native backup gate](ops-2-n8n-backup-gate.md) adds only the backup-to-database
ingress needed for a fixed native capture and retained reader. I restore that exact dump/globals pair,
verify the complete extended seat export and its exact offsite bytes, and retain
independent recovery evidence before application cutover. Any temporary Job and
reader are retained until their evidence is accepted; cleanup releases their
retention and removes them in separate GitOps stages. Neither deletion nor a new
resource name is an implicit retry.

## Cutover, schedules and acceptance

After recovery acceptance, I add only the application-to-dedicated-DB ingress and
matching app egress, keep DB egress denied, change only `DB_POSTGRESDB_HOST` to
`n8n-postgres.n8n.svc.cluster.local`, and restore the recorded one application
replica. The application continues using the same database/user, password,
encryption key, PVC, image, public host, webhook URL and effective time zone.

I verify runtime connection settings, source session absence, target identity,
readiness and Argo reconciliation. I compare the full preservation evidence
before accepting API access, credential decryption, workflow publication,
registered triggers and webhook availability. Any live execution test must have
an explicitly bounded, acceptable effect; a successful health endpoint or MCP
inventory call does not prove a workflow executed successfully.

I separate pre-existing execution errors from migration regressions. Successful
execution payloads may be deliberately discarded, so retained error rows alone
do not describe the complete schedule history. I require natural scheduled
execution evidence at the actual next occurrence, with the published version,
trigger time and result recorded. A manual replay does not replace that evidence.
A weekly schedule's observation remains pending until its real scheduled time.

The backup CronJob is enabled only after accepted native and independent recovery
checks. Unsuspending can start a missed-schedule catch-up immediately. I bind that
controller-created Job to the unchanged CronJob UID and payload, inspect its
publication manifest, completion and actual mounted replica health, and record
catch-up separately from the next natural scheduled backup.

## Rollback and retention

Before the target is exposed to application writers, I can keep the source host
and resume its recorded one n8n replica through GitOps. I retain the target,
failed attempts, source capture, application PVC, new data claim and backup claim.
To stop the unused prepared target, I scale its StatefulSet to zero through
GitOps, retain the claim template and keep the backup CronJob suspended; I do not
prune or reset data directories or credentials. Removing resources is a separate
reviewed retirement stage, not an activation rollback.

Once any n8n app pod starts on the target, startup, trigger registration and
background work may write data. I freeze it before rollback, retain a new target
dump/globals pair, and reconcile subsequent writes or obtain an explicit accepted
loss boundary before returning to the source. A blind host revert can lose
workflow, credential, execution or deduplication changes and repeat side effects.

I retain the original database, role, application volume and recovery archives
through the accepted parent observation period and longer while any application,
workflow or backup check is unresolved. This migration does not retire the shared
PostgreSQL instance or any other tenant's retained data.
