# OPS-2: prepare Authentik's dedicated PostgreSQL

I am moving Authentik off the shared PostgreSQL instance before n8n, preserving
its database, login role and SSO identities. This first preparation slice is
tracked in OPS-88 under OPS-2. It does not perform a migration.

The proposed resources live in
[`staging/ops-2/authentik-postgres`](../../staging/ops-2/authentik-postgres/).
No ArgoCD Application or active Kustomization references that directory. The
StatefulSet has zero replicas, the backup CronJob is suspended, and the database
has no inbound network allowance. I have not created the administrator Secret.
Publishing this preparation cannot start the database or change Authentik's
connection. I must prepare and authorize the activation change separately.

## Preflight evidence

I keep live tenant inventory, database sizes, role/catalog observations, backup
run identities and current capacity measurements in the private Tempo record
linked to OPS-2/OPS-88. None of that operational evidence is published here.
The generic procedures below must be checked against a fresh private preflight
before activation; the public GitOps manifests alone do not establish readiness.

The target data and operational-backup claims each request 5 GiB explicitly
from Longhorn. I verify available capacity, requested and actual replicas,
existing storage health and workload resource use before starting them. I also
verify independently recoverable native dump/globals backups and an actual
restore. An intact compressed archive alone does not establish recoverability.

## Image and role boundary

I verified PostgreSQL 18.6 against the [upstream release notes](https://www.postgresql.org/docs/release/18.6/)
and the Docker Hub manifest on September 8. Both server and backup client use
`docker.io/library/postgres:18.6-trixie@sha256:4ef4dbc939d61acea57712655ddb4b4ab27419c913f94cca0cd57cb3ea3c2280`.
The existing shared manifest and target retain major version 18; this adds the current minor fixes
while preserving the Authentik chart/image at 2026.5.6. I use a logical restore
onto a fresh volume, not a physical copy or an in-place source upgrade.
The target mounts `/var/lib/postgresql` with explicit
`PGDATA=/var/lib/postgresql/18/docker`, following the PostgreSQL 18 image layout.

The target bootstrap role and database are both `postgres`. I must supply a
new namespace-local, SOPS-managed `authentik-postgres-admin` Secret with key
`password` through the user-operated credential procedure before activation.
There is intentionally no plaintext placeholder or generated credential here.
The existing `authentik-secrets` password and secret key remain unchanged.

I do not bootstrap with `POSTGRES_USER=authentik`: the image would make the app
a superuser. I restore the existing Authentik role with its original attributes,
password verifier and required settings before restoring its database. The new
admin credential must not be overwritten by the shared instance's globals.

## Preparation and activation boundaries

The staged policy named `authentik-egress` replaces the existing policy of that
name during a later GitOps integration; it narrows its selector to Authentik
chart pods while preserving their current destinations. Database and backup
pods use the distinct `authentik-postgres` name label. Simply adding a second
restrictive policy cannot subtract the current namespace-wide egress allowance.

Before activating the first database pod, I prepare a reviewed integration diff:

1. Move the staged database and backup resources into the existing Authentik
   workload Kustomization, replace its existing egress policy, and retain the
   namespace's default-deny policy. Use the existing `authentik-config`
   Application and AppProject permissions; do not create a second reconciler.
2. Add the encrypted administrator Secret and KSOPS reference after the operator
   has created the credential. Validate it through the constrained SOPS helper,
   without printing any value, identity or decrypted manifest.
3. Set only the dedicated database StatefulSet to one replica. Leave the backup
   job suspended, application connection unchanged, and database ingress denied.
   Local pod-exec restore access remains the administrative path. No cloned
   Authentik worker/server is started in this step.
4. Render, validate and review that exact diff. Merge only with explicit rollout
   authorization. After sync, verify fresh claim identity, healthy replicas,
   server readiness, source health and unchanged live SSO.

The integration, credential entry and activation are outstanding work, not
changes already included in this preparation. No imperative apply is the
deployment procedure. I do not delete or modify source data, roles, backups,
services, tenant-init configuration or the local disk at this stage.

## Restore rehearsal gate

Before any production switch, I prepare and test the operator-run capture/import
helper against synthetic credentials and an isolated PostgreSQL instance. That
helper is not supplied by this manifest preparation. It must enforce these
contracts and stop on a mismatch:

- Capture a fresh `pg_dump -Fc` of Authentik plus complete shared globals into
  private mode-0600 recovery storage with a manifest and checksums. Keep complete
  globals for recovery, but import only the Authentik role and its demonstrated
  dependencies into the dedicated target. Never print dump contents, role
  password verifiers or application records in logs or tool output.
- Inspect role settings, grants/default privileges, database ACLs, ownership,
  extensions, tablespaces and cross-role dependencies. Limited catalog checks
  do not prove all of these are absent. Abort on
  unexpected dependencies rather than silently dropping privileges.
- Do not treat `pg_dumpall --role` or `--exclude-database` as a role filter.
  PostgreSQL's [globals exporter](https://www.postgresql.org/docs/18/app-pg-dumpall.html)
  exports cluster roles. Derive a narrowly scoped, SQL-aware role import in the
  operator helper; a grep over secret-bearing SQL is not an adequate filter.
- Restore that role import with `psql -X -v ON_ERROR_STOP=1` into the fresh
  target, then restore the custom database archive with
  `pg_restore --exit-on-error --create` connected initially to `postgres`.
  Preserve the source encoding, locale, owner and ACLs. Use the pinned 18.6
  client and analyze after restoration. Never use `--clean` against the source.
- The target already contains the bootstrap `postgres` role. Exclude its
  CREATE/ALTER statements explicitly. Do not disable error handling to hide
  duplicate-role errors, import unrelated Sure/Plane/n8n roles, or replace the
  administrator's password. Dedicated-instance recovery later needs its own
  explicit bootstrap-role collision procedure as well.
- Verify every table's row count and every sequence's `last_value`/`is_called`,
  along with schema/extension/ownership metadata and constraints, against the
  final capture after writers are frozen. Live sequence state is not MVCC
  snapshot-consistent; counting sequence objects alone is insufficient.
  Verify application-role
  TCP authentication with its existing secret, and prove it remains nonsuperuser.
  Route any necessary credential provisioning through the operator procedure.
- Keep the restored database isolated from production app pods until cutover.
  A rehearsal Authentik worker could send mail or perform real background work;
  any later application-level clone needs separate identities, restricted egress
  and an explicitly reviewed test plan. SQL-only validation does not prove SSO.

The rehearsal measures import duration and checks HDD-backed database behavior.
Any refresh destroys only the explicitly identified rehearsal copy, after its
evidence is retained and that destructive action is authorized. It never points
at the source pod or replaces a live database implicitly.

## Cutover and acceptance gate

I prepare the exact writer-freeze, backup-exporter and connection-change diffs
after rehearsal passes, then obtain authorization for the measured outage.

1. Record the current server and worker replicas, exact revisions, all affected
   SSO clients, stable user IDs/account counts, and a working recovery/admin
   login. The coordinator sees aggregate results only. Freeze both Authentik
   server and worker through their Helm GitOps values; wait for zero application
   sessions before the final consistent capture. Do not leave a worker writing.
2. Retain a final complete source dump/globals set outside normal rotation, with
   independently recoverable encrypted coverage and checksums. Restore the
   final capture into the verified target after the explicit refresh gate.
3. Add DB ingress for only Authentik chart pods and the named backup component
   in the same namespace, plus matching app egress to the dedicated DB on 5432.
   Keep database egress denied. In the Authentik Helm values change only
   `authentik.postgresql.host` to
   `authentik-postgres.authentik.svc.cluster.local`; keep database/user, secret
   references, chart version and secret key. Restore the recorded replica counts
   only after the final target validation passes.
4. Verify server/worker health, portal login/logout, recovery/admin login, and
   every active downstream OIDC/SAML client including Matrix/MAS. Compare stable
   identity and account counts, rather than accepting a new duplicate account
   that happens to log in. Verify redirects, group/claim mappings, sessions and
   background work. Capture failures without exposing claims or user records.
5. Enable the proposed logical backup only after an authorized successful manual
   capture and actual isolated restoration. The scheduled pair includes a
   custom DB dump and globals, validates both, and promotes a complete run
   atomically. Prove a natural scheduled run afterward.
6. Before acceptance, update and install the private seat exporter to capture
   `authentik.dump` and `authentik-globals.sql` from the new pod while retaining
   the shared archive. Its integration must preserve the target administrator:
   this target uses `POSTGRES_USER=postgres`, `POSTGRES_DB=postgres`, and explicit
   dump database `authentik`. Add both artifacts to the expected set. Verify local
   publication, offsite snapshot membership, independent credentials and actual
   restore; an in-cluster backup PVC alone is insufficient.

After healthy cutover, I retain the original Authentik database, role, secret,
source instance and storage through the parent issue's multi-day healthy soak,
and longer if any client/backup check remains unresolved. I record the exact
minimum duration in the cutover package before starting that clock; this
preparation does not begin a soak or shorten another Talos retention period.
Record the start/end evidence and
retain the final pre-cutover archive outside rotating backups. Remove the
source connection allowance only in a later reviewed diff.

## Rollback and remaining OPS-2 work

Before target writes, stop any target-connected app pods and return the host
value to the retained source through GitOps, then restore the recorded replicas
and revalidate SSO. Keep the target for diagnosis. Scaling it to zero retains
the data; deleting a claim is not a rollback step.

After target writes, pointing back to the old source loses those writes and
can invalidate identity/session changes. I first freeze both writers, capture
the new state, and explicitly choose either an accepted data-loss boundary or
a rehearsed reverse logical migration. A Git revert alone is not lossless data
rollback. Never run both production app sets against divergent databases.

Authentik preparation does not complete OPS-2. Next come the authorized target
bootstrap and rehearsal, Authentik cutover/backup/soak, then n8n with preservation
of its encryption key, PVC, published workflows, credentials and natural
schedules. Sure/Plane recovery retention remains coordinated with OPS-66/OPS-7.
The shared instance cannot be retired just because those apps have no pods.

Only after every tenant has a validated destination or separately accepted
retirement can I prepare source StatefulSet/PV/node-local disk removal. Retain
final database and globals backups outside rotation, verify all references and
backup manifests, and run clean Terraform validation. That destructive change
requires separate explicit authorization and its own storage rollback limits.

## Preparation validation

The eight-resource Kustomize graph renders and passes strict kubeconform checks
with no skipped rendered resources. All eight objects pass the live apps API's
server-side dry-run admission. The checked policy union includes the existing
namespace policies: chart app egress stays available, database ingress/egress
is empty, and the backup can only attempt DNS and its own database. No active
root references this preparation, and no Secret object is included. CI now
checks the staging manifests alongside the existing cluster manifests.

Independent review and synthetic execution of the backup shell body verify
complete publication, private artifact modes, relative manifest paths,
seven-run retention, and preservation of the previous current generation
when globals export, role coverage, dump or archive validation fails. These
checks use fake PostgreSQL clients; they do not establish actual runtime,
restore or performance acceptance. Runtime startup remains untested because
no target or credential was created.
