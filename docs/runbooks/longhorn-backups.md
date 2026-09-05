# Longhorn backups to Backblaze B2

I manage the backup target through the pinned Longhorn chart Application and
credentials, network policy and scheduling through `longhorn-config`.
Merging these manifests deploys them through ArgoCD auto-sync.

## Configuration and scope

- Target: `s3://fleet-longhorn-backups@us-east-005/`; poll every 300 seconds.
- Endpoint: `https://s3.us-east-005.backblazeb2.com`.
- Secret: `longhorn-system/longhorn-b2-backups`, encrypted with the apps cluster
  age recipient and rendered by KSOPS. It holds `AWS_ACCESS_KEY_ID`,
  `AWS_SECRET_ACCESS_KEY` and `AWS_ENDPOINTS`.
- Schedule: `nightly-b2`, `0 6 * * *`, task `backup`, retain 7 backups per
  volume/job, concurrency 1, group `default`. The controller creates a CronJob
  with `Forbid` overlap handling. Longhorn 1.12.0 does not expose a timezone
  field; 06:00 uses the Kubernetes controller's timezone, which needs runtime
  verification. This schedule has no ordering dependency on database dumps.
- Detached volumes may be temporarily attached to run their backup.

All 23 current Longhorn volumes have the default recurring-job group enabled
and use the default backup target (checked 2026-09-05). Recheck membership when
adding workloads or custom recurring jobs. The local-manual shared PostgreSQL
volume is outside this scope. Native database dumps **and globals** remain
required: these volume snapshots are crash-consistent, not a database restore
rehearsal or a quiesced migration copy.

I use a separate private B2 bucket and bucket-scoped read/write/delete key from
the existing restic pipeline. Enable B2-managed server-side encryption. Do not
configure bucket expiration or default Object Lock retention: Longhorn owns
shared block retention and deletion. Preserve recovery access outside the
cluster. Bucket settings and authenticated access remain rollout checks;
valid ciphertext alone cannot prove either. B2's free storage allowance is
shared across the account, not renewed for each bucket.

## Rollout impact

The existing Longhorn chart/image versions stay pinned. Rendering the old and
new chart values changes only the default-resource and default-setting
ConfigMaps, not workload pod templates. The first backup uploads used data;
later runs upload changed blocks and add storage I/O and outbound traffic.

The complete Cilium allow policy is applied before the explicit default-deny
NetworkPolicy. It permits internal storage traffic, API and DNS access, node
storage/probe/webhook connections, and external HTTPS for B2. Introducing this
policy starts enforcing isolation immediately on existing Longhorn endpoints;
check attachment and application I/O after sync. Current claims are RWO. A
future RWX consumer needs its own reviewed NFS ingress allowance.

Longhorn 1.12.0's RecurringJob controller does not provide container resource
settings. A namespace LimitRange supplies requests of 50m CPU / 128Mi memory
and limits of 2 CPU / 4Gi memory wherever omitted at admission. This applies
to new backup containers **and future replacement storage containers**.
Existing pods are unchanged, and explicit container resources take precedence.
These are admission defaults, not namespace maximum constraints. Inspect the
first backup's usage and any OOM/throttling before changing the defaults.

Two database volumes (MoneyMatter and Tempo) currently have one healthy replica
and insufficient allocation headroom for a second replica. Backups do not fix
that degradation; resolve the storage allocation separately and verify that
both degraded volumes still receive completed backups.

## Verification after authorized merge

1. Confirm `longhorn` and `longhorn-config` are Synced/Healthy. Verify KSOPS
   successfully rendered the Secret without displaying its values.
2. Check the target after a poll; require `AVAILABLE=true`, a fresh sync time
   and no error conditions:

   ```bash
   kubectl --context apps -n longhorn-system get backuptargets.longhorn.io default \
     -o custom-columns=NAME:.metadata.name,AVAILABLE:.status.available,SYNCED:.status.lastSyncedAt
   kubectl --context apps -n longhorn-system get backuptargets.longhorn.io default \
     -o jsonpath='{.status.conditions}'
   ```

3. Check existing workloads, volume attachment and storage component health.
   Verify the generated CronJob, controller timezone and admitted backup pod
   requests/limits. Do not patch controller-generated CronJobs manually.
4. After the scheduled run, require completed backups with no errors and a
   populated last-backup record for every retained Longhorn volume:

   ```bash
   kubectl --context apps -n longhorn-system get backups.longhorn.io \
     -o custom-columns=NAME:.metadata.name,VOLUME:.status.volumeName,STATE:.status.state,PROGRESS:.status.progress,ERROR:.status.error
   kubectl --context apps -n longhorn-system get volumes.longhorn.io \
     -o custom-columns=NAME:.metadata.name,BACKUP:.status.lastBackup,AT:.status.lastBackupAt
   ```

   Inspect backup job logs and remote object presence; account explicitly for
   any missing volume. Keep operational output in private records. If access
   fails before the scheduled run, stop recurrence through GitOps while fixing
   the cause. Any earlier manual test must also be prepared as a GitOps Job.
5. Prove restore separately: select a completed `mealie-data` backup, prepare
   a GitOps change restoring its exact backup URL into a new isolated scratch
   PVC with explicit `storageClassName: longhorn`, then inspect known files
   through a read-only mount in a resource-limited pod. Never connect it to a
   production application. Record the result before a separately approved
   cleanup. Restore database dump/globals pairs separately.

Preparation validation covers YAML/installed CRD server dry-run, the chart
render comparison, and ciphertext structure/recipient. It does not decrypt the
Secret, authenticate to B2, prove live policy connectivity, or prove restore.

## One-time preflight run — 2026-09-05

I requested an immediate first run instead of waiting for the nightly schedule.
`longhorn-backup-first-run-20260905` uses the generated nightly Job's command,
service account, image and engine-binary mount, with explicit resource budgets.
The image stays at the deployed 1.12.0 release to match the manager. It uses the
existing nightly-b2 policy, including serial volume processing and retention.

This ordinary GitOps Job runs once when synced, has no automatic retry, and
has a two-hour deadline. It is not a recurring hook and has no TTL: retaining
the terminal Job prevents ArgoCD from recreating it. The nightly CronJob's
Forbid policy does not cover this standalone Job; check that no run is active
before deploying it and observe completion before the next scheduled run.
The first run was prepared with no active backup jobs and 5.68 GiB of reported
Longhorn actual volume data, which is not an exact forecast of uploaded bytes.

Verify its outcome and every volume's completed backup before removing the
Job manifest and Kustomization entry in a later GitOps cleanup. To stop the
one-time run, remove those same entries and let ArgoCD prune the Job; inspect
engine backup status afterward, since stopping the runner does not prove every
in-flight engine operation stopped. Preserve remote backup objects. A failed
Job is evidence to investigate, not authorization for repeated retries.

## Rollback

Stop recurrence first: remove `04-recurring-backup.yaml` from the companion
Kustomization through GitOps and let ArgoCD prune the RecurringJob. Inspect
in-flight jobs before continuing; removing their owner can also remove
controller-owned work, so do not treat an interrupted upload as completed.
Keep the target, Secret, bucket and completed remote backups available for
recovery. If reverting detached-volume behavior, explicitly set
`allowRecurringJobWhileVolumeDetached: false` in chart values.

For a connectivity regression, remove **both** `01-netpol.yaml` and
`01b-node-netpol.yaml` from the companion Kustomization in a GitOps rollback.
Removing only the allow policy leaves default-deny in place. Remove the
LimitRange too if its admission defaults cause replacement pod problems;
existing admitted pods keep their resources until replaced.

Keep the companion Application while pruning these resources; deleting that
Application first can orphan them. The namespace has `Prune=false` to protect
live storage. Do not uninstall Longhorn or delete volume/backup objects as
rollback. Simply omitting backup-target chart values is not a reliable way to
clear a previously persisted BackupTarget; preserving it is intentional.

## References

- [Longhorn recurring jobs](https://longhorn.io/docs/1.12.0/snapshots-and-backups/scheduling-backups-and-snapshots/)
- [Longhorn backup targets](https://longhorn.io/docs/1.12.0/snapshots-and-backups/backup-and-restore/set-backup-target/)
- [Longhorn networking](https://longhorn.io/docs/1.12.0/references/networking/)
- [Backup architecture](../adr/0008-backup-architecture.md)
