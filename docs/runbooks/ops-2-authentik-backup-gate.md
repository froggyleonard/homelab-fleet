# OPS-2: native backup gate with Authentik frozen

I apply this slice only after the final source capture has been imported once
and accepted in the dedicated database. Both Helm replica counts remain zero,
the application host remains `postgres.postgres.svc.cluster.local`, and no
server/worker pods or application sessions may exist. I retain the accepted
source/target identities, final capture, restore receipt and existing-password
SQL login evidence privately before opening the backup path.

This slice adds one backup-only database ingress policy and the fixed ordinary
Job `authentik-pg-backup-ops2-final-gate`, followed by the fixed read-only Pod
`authentik-pg-backup-ops2-final-reader`. The existing backup egress already
permits namespace-local database TCP 5432 and cluster DNS. The new ingress permits
only `authentik-postgres` / `backup` pods in the same namespace on TCP 5432.
Application access, all database egress and all backup ingress remain denied.
The network policy uses sync wave `-1`, before the default-wave Job in the same
configuration Application. The reader has wave `1`: normal Job health must
reach completion before that later wave begins. I verify the policy union and
the frozen chart Application before accepting the run; waves do not order
separate Applications.

The Job uses the suspended CronJob's exact container, command, environment,
Secret references, labels, volume and resource settings. Three Job-only execution
controls differ: `activeDeadlineSeconds: 900`, `backoffLimit: 0` and
`restartPolicy: Never`. A stuck capture is terminated after the 15-minute deadline
without retry, retaining the failed Job/pod evidence and backup claim.
No hook, generated name, TTL or automatic retry is configured. The fixed Job has
`Prune=false,Delete=false` and remains after completion or failure. I do not
rename or delete it or its pod to rerun it: ArgoCD would recreate a missing
managed Job. Failure requires inspection and a separately prepared next action.
The recurring CronJob remains suspended throughout this gate. The reader is
a normal retained Pod, not a Job sidecar that would prevent Job completion.

The command starts Bash directly and never runs initdb or creates a database or
role. It connects as the existing `postgres` administrator using
`authentik-postgres-admin/password`, exports complete dedicated-instance globals
from `postgres`, and dumps the explicit `authentik` database. Its role-coverage
check includes the local bootstrap and imported application login roles. The
existing backup claim is mounted at `/backups`. Both backup templates run as
UID/GID 999, with `runAsNonRoot`, `fsGroup: 999` and
`fsGroupChangePolicy: OnRootMismatch`. This lets the writer create its private
directories with permission bits 0700 and 0600 files as the same nonroot
identity that will read them. Directories may inherit the volume root's setgid
bit, yielding mode 2700 without granting additional access.
The writer also has a read-only root filesystem, RuntimeDefault seccomp, no
capabilities and no privilege escalation; its only writes are to the backup
claim. The initial writer mount may update that claim's group permissions as
specified by its fsGroup. No data or backup claim, PGDATA, image, ciphertext or
bootstrap setting changes. I verify the bound backup claim,
its first mount, available capacity and two actual healthy Longhorn replicas
before calling this operational backup coverage.

The reviewed payload stages a new private generation, verifies complete globals,
role coverage and the custom archive's table of contents, then atomically
publishes the pair and its checksum manifest. It preserves an existing current
generation if capture or validation fails. Its normal seven-generation retention
still applies. I retain this exact gate generation outside rotating backups
before enabling any later schedule. The dump, globals and manifest remain private;
I do not print their contents or copy them into this public repository.

A completed Job establishes capture only. Its terminated pod cannot service
`kubectl exec`, so I use the separate fixed reader after verifying that exact
Job's completion. The reader runs only `sleep 3300`, providing a 55-minute
readback window
with a 3600-second hard active deadline and `restartPolicy: Never`. Normal
completion succeeds before the deadline; unusually slow startup may still
reach DeadlineExceeded. It has the same pinned image but an overridden
command, no initdb, database connection, environment/Secret references, init
containers, sidecars or API token. It runs as UID/GID 999 with RuntimeDefault
seccomp, dropped capabilities, no privilege escalation and a read-only root.
Both its PVC source and `/backups` mount are read-only. It has no fsGroup, so
its mount requests no ownership rewrite. The `backup-reader` component label
matches only the namespace default-deny policy, granting no DB, DNS or other
network access.

I bind readback to the completed Job UID and its successful owned pod UID, then
the command's single strict `published <timestamp.suffix>` result. I read only
that exact `/backups/runs/<timestamp.suffix>` directory; I do not follow a later
`current` generation or an arbitrary user-supplied path. I require the expected
regular files, private owner/modes, exact MANIFEST sizes and SHA256s, stable
reader pod/container and PVC/PV identities, and the retained Longhorn volume
handle. While the read-only reader holds the volume attached, I verify two
actual healthy running replicas in RW engine mode; a configured count of two
or a detached/unknown volume is insufficient. The protected private consumer
streams only the MANIFEST and its named pair, checks hashes after copying, and
rechecks its source identities. It never emits SQL or dump bytes to a terminal.

While writers remain frozen, I read back and checksum that exact published
generation and restore it into a separate fresh disposable PostgreSQL instance using the reviewed private recovery helper.
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
and restore the recorded replica counts. I preserve this Job and reader Pod's
names, definitions and Kustomize references unchanged so ordinary reconciliation
does not execute them again. The recurring CronJob stays suspended until its
separate enablement gate.
I do not blindly replace this graph with an earlier cutover tree that predates
the retained Job.

## Rollback and retention

The reader provides a finite readback window, not an indefinite service. After
normal expiry I retain its Succeeded result. If its hard deadline expires first,
I retain DeadlineExceeded and inspect the accepted copy or failure evidence.
I never delete,
rename or remove/re-add the reader to manufacture another window. Its `Never`
restart policy prevents container restarts, but deleting a still-managed Pod
would let ArgoCD recreate it. Any replacement requires an explicit new reviewed
stage, not an implicit retry.

A failed gate does not resume writers, replay the database import or reset either
PGDATA directory. I retain the failed Job/pod and accepted captures for diagnosis.
A GitOps change may remove only `authentik-postgres-ingress` to close backup access;
the original five policies, frozen source host and both replica counts remain.
Revoking access is not proof that a running export has stopped: I verify that its
pod has terminated before treating the gate as finished.

For cleanup, I first preserve the Job's result, exact readback/restore receipts
and required artifacts privately. I schedule reader cleanup after accepted
readback and retain its completed result until then. Removing either
file/reference alone deliberately leaves its live resource retained because
pruning is disabled. When cleanup is intended, I prepare a GitOps
change setting only the selected Job or reader Pod's retention annotation to
`Prune=true,Delete=true`, let it reconcile, and then remove its manifest/reference
in a separate change. I remove the backup-only gate policy only when its later
cutover ownership allows that change. I verify the selected pod is gone and
no replacement is created. Cleanup never starts the backup again. The PVC
has its own unchanged retention annotation; deleting the Job does not remove the
claim or its files. I never use deletion, a new name or re-adding the Job as an
implicit retry. After app cutover, I use the main migration rollback procedure
and account for target writes before returning the host to the retained source.

## Reader preparation validation

The Job and CronJob pod/container payloads remain identical apart from the
already documented Job execution controls. Their dump/validation/publication
shell is unchanged. A disposable PostgreSQL fixture executes that exact shell
as UID/GID 999 against a tmpfs backup volume with the writer's group-access
envelope. A separate nonroot read-only consumer reads all three private files
with identical hashes; writes to its backup mount and root filesystem fail.
The fixture uses no production data, credential, host mount or network.

All four built-in resource documents pass strict schema validation, and the
three changed/new workload objects pass server-side dry-run admission. The
reader's desired labels match no allow policy in the complete namespace policy
union. These preparation checks create no cluster resource. Actual Job/pod
identities, CSI mount ownership, Longhorn replica completion, exact artifact
readback and the globals-first recovery test remain execution acceptance.
