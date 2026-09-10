# OPS-2: n8n native backup gate while writers are frozen

I apply this gate only after the final frozen source capture has been imported
once and accepted in the dedicated database. The n8n Deployment remains at zero
replicas with its original shared-source host. I require no n8n application pod
or source application session, the accepted source/target identities, complete
SQL restore verification and the existing-password login receipt before opening
backup access. The [main migration runbook](ops-2-n8n-postgres.md) owns the full
application, publication, credential, recovery and observation requirements.

## Fixed capture and reader

The new `n8n-postgres-ingress` policy permits only same-namespace
`n8n-postgres` / `backup` pods to reach the dedicated DB on TCP 5432. Its sync wave
is `-1`. The default wave contains one ordinary fixed Job,
`n8n-pg-backup-ops2-final-gate`; wave `1` contains the fixed read-only Pod,
`n8n-pg-backup-ops2-final-reader`. All resources belong to the same n8n ArgoCD
Application. The application remains frozen on its source, application access
to the target remains blocked, and DB egress remains denied.

The Job copies the suspended `n8n-pg-backup` CronJob's exact pod/container payload,
including Secret references, command, environment, volumes, ownership, labels and
resources. Only its execution controls differ: `activeDeadlineSeconds: 900`,
`backoffLimit: 0` and `restartPolicy: Never`. It has no hook, TTL, generated name or
automatic retry. It is retained with `Prune=false,Delete=false` after success or
failure. This stage does not resume the application or enable the CronJob.

The payload uses `n8n-postgres-admin/password` to export complete dedicated-instance
globals from the `postgres` database and a custom dump of the explicit `n8n`
database. It never starts initdb, creates a database/role or changes an existing
credential. It checks globals completion and role coverage, validates the custom
archive, and publishes a complete generation and MANIFEST atomically under
`/backups/runs/<timestamp.suffix>`. Seven-generation retention remains unchanged;
I preserve this final gate generation outside rotation before enabling schedules.

Both backup templates run as UID/GID 999 with fsGroup 999 and OnRootMismatch.
The writer may establish group ownership on its backup mount; it writes only to
that claim and creates private files with permission bits 0600. Private directories
may inherit setgid, giving mode 2700 instead of 0700 without adding access. I
verify the actual mount ownership, free space and two healthy RW Longhorn replicas.
No application PVC, database claim, PGDATA, image pin or ciphertext changes here.

A completed Job's terminated pod cannot serve `kubectl exec`. The separate reader
runs the same pinned image with only `sleep 3300`, a 3600-second active deadline
and restartPolicy Never. It has no environment, credentials, API token, sidecar,
init container, database startup or network allowance. UID/GID 999 matches the
writer, but the reader has no fsGroup and requests a read-only PVC source, mount
and root filesystem. Its `backup-reader` labels match no allow policy in the
full namespace policy union.

## Evidence and recovery acceptance

I bind the exact Job UID to its successful owned pod UID and single strict
`published <timestamp.suffix>` log result. I bind the separate reader UID and
container identity to the retained backup PVC/PV/Longhorn identities, and verify
two actual healthy running replicas in RW mode while it keeps the volume attached.
I read only the fixed generation's MANIFEST, `n8n.dump` and `n8n-globals.sql`,
checking regular-file ownership, modes, sizes, hashes and stable before/after
identity. I do not read through a mutable `current` symlink or print archive/SQL
contents.

The copied pair is restored globals-first into an isolated PostgreSQL instance
and compared against the accepted frozen source baseline, including every table,
sequences, role and administrator preservation, credentials, settings and workflow
publication bindings. Capture completion alone does not prove recovery. I retain
the independently verified seat/offsite bytes and application-PVC recovery
coverage before resuming application writers.

The reader intentionally keeps the n8n Argo Application `Progressing` while this
ordinary Never-restart pod is still running. This is expected only for the exact
accepted Ready/Running sleep-only reader, with the completed fixed Job, all desired
resources Synced and no unrelated unhealthy resource. I record the actual health
and pending cleanup explicitly. I require normal Healthy reconciliation after
the reader is removed; I do not describe the temporary Progressing state as Healthy.

## Cutover, rollback and cleanup

The later cutover extends this policy to the exact n8n app selector, adds matching
app egress to the dedicated DB, changes only its database host and restores the
recorded application replica count. It preserves this Job and reader unchanged,
so reconciliation does not execute the backup again. The CronJob remains suspended
until its separate accepted enablement stage.

A failed gate does not resume writers, replay the import or reset the target.
I preserve failure evidence and retained data. Before any target application
writer starts, rollback keeps the original source host and restores one source
app replica through GitOps. I can remove only this new backup ingress to close
access, but verify that the backup pod has actually terminated before considering
capture stopped. Once target app pods have started, I follow the main runbook's
freeze-and-reconcile procedure before returning to the source.

After accepted readback and recovery, I preserve Job/reader results privately.
Cleanup first changes only their retention annotations to
`Prune=true,Delete=true`, waits for those exact existing resources to reconcile,
and then removes both manifest files and Kustomize references in a separate
change. I verify the Job, its owned pod and the reader are gone and no replacement
appears. Claims and backup files remain retained. I do not delete, rename,
remove/re-add or revert the removal of either temporary resource as an implicit
retry. The cutover owns the resulting DB ingress policy; cleanup does not remove
application or backup access that the accepted cutover still requires.
