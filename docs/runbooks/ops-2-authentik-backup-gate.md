# OPS-2: native backup gate with Authentik frozen

I apply this slice only after the final source capture has been imported once
and accepted in the dedicated database. Both Helm replica counts remain zero,
the application host remains `postgres.postgres.svc.cluster.local`, and no
server/worker pods or application sessions may exist. I retain the accepted
source/target identities, final capture, restore receipt and existing-password
SQL login evidence privately before opening the backup path.

This slice adds one backup-only database ingress policy and the fixed ordinary
Job `authentik-pg-backup-ops2-final-gate`. The existing backup egress already
permits namespace-local database TCP 5432 and cluster DNS. The new ingress permits
only `authentik-postgres` / `backup` pods in the same namespace on TCP 5432.
Application access, all database egress and all backup ingress remain denied.
The network policy uses sync wave `-1`, before the default-wave Job in the same
configuration Application. I verify the policy union and the frozen chart
Application before accepting the run; waves do not order separate Applications.

The Job uses the suspended CronJob's exact container, command, environment,
Secret references, labels, volume and resource settings. Three Job-only execution
controls differ: `activeDeadlineSeconds: 900`, `backoffLimit: 0` and
`restartPolicy: Never`. A stuck capture is terminated after the 15-minute deadline
without retry, retaining the failed Job/pod evidence and backup claim.
No hook, generated name, TTL or automatic retry is configured. The fixed Job has
`Prune=false,Delete=false` and remains after completion or failure. I do not
rename or delete it or its pod to rerun it: ArgoCD would recreate a missing
managed Job. Failure requires inspection and a separately prepared next action.
The recurring CronJob remains suspended throughout this gate.

The command starts Bash directly and never runs initdb or creates a database or
role. It connects as the existing `postgres` administrator using
`authentik-postgres-admin/password`, exports complete dedicated-instance globals
from `postgres`, and dumps the explicit `authentik` database. Its role-coverage
check includes the local bootstrap and imported application login roles. The
existing backup claim is mounted at `/backups`; no data or backup claim, PGDATA,
image, ciphertext or bootstrap setting changes. I verify the bound backup claim,
its first mount, available capacity and two actual healthy Longhorn replicas
before calling this operational backup coverage.

The reviewed payload stages a new private generation, verifies complete globals,
role coverage and the custom archive's table of contents, then atomically
publishes the pair and its checksum manifest. It preserves an existing current
generation if capture or validation fails. Its normal seven-generation retention
still applies. I retain this exact gate generation outside rotating backups
before enabling any later schedule. The dump, globals and manifest remain private;
I do not print their contents or copy them into this public repository.

A completed Job establishes capture only. While writers remain frozen, I read
back and checksum that exact published generation and restore it into a separate
fresh disposable PostgreSQL instance using the reviewed private recovery helper.
I restore the required globals before the database, handle the already-existing
bootstrap role explicitly, and preserve its credential rather than ignoring SQL
errors or replaying the dedicated administrator over another bootstrap. I verify
roles/verifiers, schema, table contents/counts and sequence state. I also require
the independently recoverable coverage and authenticated recovery access from
the main migration runbook. This PVC is not an offsite backup, and a successful
`pg_restore --list` is not a restore test.

## Cutover integration

Only after native recovery is accepted do I build the later cutover on this
commit. I extend the existing `authentik-postgres-ingress` policy to allow the
same-namespace Authentik chart server/worker labels as well as backup, add the
matching app egress, change the chart database host to the dedicated service,
and restore the recorded replica counts. I preserve this Job's name, definition
and Kustomize reference unchanged so ordinary reconciliation does not execute it
again. The recurring CronJob stays suspended until its separate enablement gate.
I do not blindly replace this graph with an earlier cutover tree that predates
the retained Job.

## Rollback and retention

A failed gate does not resume writers, replay the database import or reset either
PGDATA directory. I retain the failed Job/pod and accepted captures for diagnosis.
A GitOps change may remove only `authentik-postgres-ingress` to close backup access;
the original five policies, frozen source host and both replica counts remain.
Revoking access is not proof that a running export has stopped: I verify that its
pod has terminated before treating the gate as finished.

For cleanup, I first preserve the Job's result and required artifacts privately.
Removing its file/reference alone deliberately leaves the live Job retained
because pruning is disabled. If explicit Job removal is intended, I prepare a
GitOps change setting only that Job's retention annotation to
`Prune=true,Delete=true`, let it reconcile, and then remove its manifest/reference
and the gate policy in a separate change. I verify no gate pod remains. The PVC
has its own unchanged retention annotation; deleting the Job does not remove the
claim or its files. I never use deletion, a new name or re-adding the Job as an
implicit retry. After app cutover, I use the main migration rollback procedure
and account for target writes before returning the host to the retained source.
