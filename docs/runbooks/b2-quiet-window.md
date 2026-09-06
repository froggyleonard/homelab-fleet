# B2 quiet window (OPS-74)

I prepared a 24-hour pause to test recovery from exhausted transaction caps.
This is a temporary production change, pending authorization and coordinated
host-timer pauses. The clock starts only when all consumers are paused. I record
the actual UTC start and intended resume time in the private issue. Nothing in
these manifests automatically resumes after 24 hours.

## Cluster change

- Set the pinned Longhorn chart's catalog poll interval to zero.
- Omit `04-recurring-backup.yaml` from Kustomization so ArgoCD prunes the
  RecurringJob and its owned nightly CronJob. The file remains ready for resume.
- Remove only Longhorn's world TCP/443 egress allowance. Internal Longhorn
  traffic, API access, DNS and existing node ingress rules remain unchanged.

Longhorn 1.12.0 stops its scheduled timer at zero, but failed sync requests can
remain outstanding and retry on controller events. The temporary egress
restriction prevents these requests reaching B2. Blocked connection errors and
an unavailable backup target are expected during the window. I do not clear
the target URL, remove credentials, uninstall storage, or delete backups.

No storage workload template or image changes. Application I/O should continue;
check mounted volumes and application health after reconciliation. Off-site
freshness ages during this window; existing local dumps and VM archives keep
their schedules. Avoid manual backup/restore tests and repeated catalog reads.

## Coordinated rollout

1. Verify there are no active Longhorn backup Jobs or engine backup operations.
   Preparation observed no active Jobs; repeat immediately before merge. Do not
   interrupt an upload merely to hit the proposed start time.
2. Pause the seat's `offsite-push.timer` and the verified pve B2 consumers using
   the private handoff. Include integrity/freshness checks that read restic;
   pausing only uploads does not stop read transactions. Privileged steps are
   operator-run. Preserve local producers and record each timer's prior state.
3. Merge this scoped change after authorization. Confirm both `longhorn` and
   `longhorn-config` reconcile. Confirm the default BackupTarget poll interval
   is zero, the nightly RecurringJob/CronJob are absent, and the allow policy
   no longer permits world HTTPS. Keep the completed first-run Job so it is
   not accidentally recreated.
4. Verify storage attachment, replica health, application I/O and Cilium policy
   realization. Check account request counters rather than actively probing B2
   from the paused consumers. Inspect clusterwide policies for another allowance
   if counters continue growing. This namespace policy does not stop unrelated
   B2 clients elsewhere in the account.
5. Keep the pause across the next midnight UTC and for the intended 24 hours.
   Backblaze documents the reset at midnight; inactivity is not its stated
   prerequisite. A quiet window tests immediate re-exhaustion and other consumers.

## Controlled resume and rollback

At the recorded review time, first check the account's reset/cap state. Resume
one consumer at a time and watch requests. With Longhorn still blocked, run one
pve metadata check for OPS-69 after the reset; do not start integrity scans or
all persistent timers simultaneously. If access still fails, retain the exact
error and investigate account/key permissions; do not assume every AccessDenied
is a cap error.

Restore the world TCP/443 rule through GitOps, initially leaving polling at zero
and recurrence omitted. A pending sync may immediately run. Check target
availability, lastSyncedAt and quota use. Restore hourly polling (`3600`) and
the Kustomization recurring-job entry only when that check passes. Resume host
timers from their recorded prior state; Persistent timers may run missed jobs
immediately. Record the resumed jobs and next trigger times.

For a storage connectivity regression, revert this pause commit through GitOps
to restore its exact prior allow rule, hourly polling and nightly schedule.
That also ends the quiet window and can consume the cap again. Keep the
namespace, target, credentials and backup data intact. Resume only timers paused
for this operation. Do not change the earlier hourly mitigation back to 300.

Acceptance remains target availability with an advancing catalog sync, complete
per-volume accounting after the next nightly run, and a full UTC usage day
without renewed cap errors. A pause alone does not complete OPS-74 or prove a
restore. OPS-69 separately verifies off-site snapshot membership.

References: [B2 caps and reset](https://www.backblaze.com/docs/cloud-storage-data-caps-and-alerts),
[pinned backup-target controller](https://github.com/longhorn/longhorn-manager/blob/v1.12.0/controller/backup_target_controller.go),
and [normal backup policy](longhorn-backups.md).
