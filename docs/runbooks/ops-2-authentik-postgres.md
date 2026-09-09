# OPS-2: refresh Authentik's isolated PostgreSQL

I am preparing a fresh final-restore target while retaining the rehearsal copy.
The activation and isolated SQL rehearsal are complete. This package changes
only the dedicated StatefulSet's `PGDATA` from `/var/lib/postgresql/18/docker`
to `/var/lib/postgresql/18/ops2-final` on the same retained Longhorn claim.
Merging it rolls the isolated PostgreSQL pod through ArgoCD and initializes a
fresh bootstrap cluster with the existing administrator Secret.

Authentik keeps its shared-source connection and current server/worker replicas.
The target remains denied ingress and egress, and its backup stays suspended.
This refresh precedes the separately authorized writer freeze, final capture,
restore, connection change and SSO acceptance. It does not itself migrate traffic.

## Refresh procedure and rollback

Before the merge, I use the reviewed private `refresh-authentik-db.py plan`
helper and retain its append-only record. It must bind the accepted rehearsal
capture, restore attempt and SQL/login evidence to the current source and target.
I verify both application components still use the source and are healthy, the
exact target pod/PVC/PV/volume and PostgreSQL identity, two actual healthy storage
replicas, retained claims, suspended backup, unchanged administrator Secret
metadata and bootstrap references, and the full additive network-policy boundary.

The destination must be absent, including any dangling symlink. The data mount,
parent and rehearsal path must resolve to the expected retained volume. I require
filesystem space for both copies and a conservative import/WAL reserve: at least
the greater of 2 GiB or twice the larger measured database plus 1 GiB must remain
available before refresh. I stop for an occupied path, partial initialization,
changed identity or inadequate capacity; no delete/reset/retry is implied.
I refresh this evidence within 30 minutes of the exact approved merge.

After the merge, I run `refresh-authentik-db.py verify` against its recorded plan
and the exact merged revision. I require ArgoCD Synced/Healthy, a ready replacement
pod with a new PostgreSQL system identifier, the unchanged bound data volume,
healthy replicas and the fixed final `data_directory`. Only the `postgres`
bootstrap database/role may exist, and TCP authentication must require SCRAM.
I verify that the rehearsal directory retains its original system identifier,
the existing administrator Secret/reference is unchanged and the application
still uses its original healthy source. Fresh initdb produces a new SCRAM salt;
its new bootstrap fingerprint becomes the later final-restore baseline.

The old data directory and every rehearsal artifact remain retained. These two
directories share a volume and failure boundary; they are not independent backups.
The public repository contains only this procedure and manifests. Exact live
identities, measured capacity, receipt IDs and recovery evidence remain private.

If refresh fails while Authentik still uses its source, I prepare a GitOps rollback
setting only `PGDATA` back to `/var/lib/postgresql/18/docker`. I verify the old
PostgreSQL system identifier, accepted rehearsal content and source health after
that rollout. Both directories, the claims and ciphertext remain intact. I do
not remove a partial final directory or replay initialization. A new attempt
needs an inspected and reviewed recovery plan. After application writes reach
the final database, this directory switch is no longer a data-safe rollback;
the cutover rollback procedure below applies.

## Preflight evidence

I keep live tenant inventory, database sizes, role/catalog observations, backup
run identities and current capacity measurements in the private Tempo record
linked to OPS-2/OPS-88. None of that operational evidence is published here.
The generic procedures below must be checked against a fresh private preflight
before refresh; the public GitOps manifests alone do not establish readiness.

The target data and operational-backup claims each request 5 GiB explicitly
from Longhorn. I verify available capacity, requested and actual replicas,
existing storage health and workload resource use before starting them. I verify
current native dump/globals backup coverage and preserve the shared source.
Before application cutover, I also require an actual isolated restore and
independently recoverable backups. An intact compressed archive alone does not
establish recoverability.

## Image and role boundary

I verified PostgreSQL 18.6 against the [upstream release notes](https://www.postgresql.org/docs/release/18.6/)
and the Docker Hub manifest on September 8. Both server and backup client use
`docker.io/library/postgres:18.6-trixie@sha256:4ef4dbc939d61acea57712655ddb4b4ab27419c913f94cca0cd57cb3ea3c2280`.
The existing shared manifest and target retain major version 18; this adds the current minor fixes
while preserving the Authentik chart/image at 2026.5.6. I use a logical restore
into a fresh cluster on retained storage, preserving the shared source.
The target mounts `/var/lib/postgresql` with explicit
`PGDATA=/var/lib/postgresql/18/ops2-final`; the parent mount preserves the sibling
rehearsal directory. The [official image entrypoint](https://github.com/docker-library/postgres/blob/master/docker-entrypoint.sh)
initializes the selected data directory. I test the exact pinned image with both
directories and a return to the rehearsal copy before accepting this procedure.
Initdb explicitly requires SCRAM on every TCP connection, including loopback;
local socket administration is confined to the pod-exec boundary.

The target bootstrap role and database are both `postgres`. I supplied a
new namespace-local, SOPS-managed `authentik-postgres-admin` Secret with key
`password` through the user-operated credential procedure.
Only the encrypted administrator artifact is committed; no plaintext credential is present.
The existing `authentik-secrets` password and secret key remain unchanged.

I do not bootstrap with `POSTGRES_USER=authentik`: the image would make the app
a superuser. I restore the existing Authentik role with its original attributes,
password verifier and required settings before restoring its database. The new
admin credential must not be overwritten by the shared instance's globals.

## Completed activation and remaining gates

The existing `authentik-egress` policy now selects only Authentik chart pods,
while preserving their existing destinations. Database and backup pods use the
distinct `authentik-postgres` name label. The namespace default-deny and server
Traefik ingress remain in place. Policies are additive: an extra restrictive
policy cannot subtract a namespace-wide egress allowance. The narrowed app
egress and new database/backup policies use ArgoCD sync wave `-1`, ahead of
the default-wave StatefulSet, so the policy updates precede pod creation. The
namespace uses wave `-2`, allowing the same ordering during fresh-namespace
recovery.

The completed activation integrated the database and backup resources into the
existing workload graph. This refresh retains that graph, chart values and source
connection. The backup CronJob remains suspended. The fresh directory initializes
only the bootstrap `postgres` role/database; final role import and database restore
remain separate operator-run steps.

The original administrator provisioning and activation validation are complete.
I retain the existing ciphertext and do not repeat credential generation. Current
refresh validation renders all nonsecret resources, checks strict schemas and
server admission, and proves both ciphertexts and the generator byte-identical
to the previously validated full KSOPS graph. I inspect the exact rollout diff. I verify the backup
claim when first mounted before claiming operational backup coverage.

The isolated database and operational-backup claim each request 5 GiB from the
explicit Longhorn class. Both claim declarations have `Prune=false,Delete=false`;
StatefulSet claim retention is `Retain` for deletion and scaling. To roll back
this first activation, I set only the dedicated StatefulSet to zero replicas
through GitOps and retain its claims and encrypted administrator Secret. I verify
Authentik still uses the source. Claim deletion and credential removal are
separate actions, not implicit parts of rollback.

No imperative apply is the deployment procedure. I do not modify source data,
roles, backups, services, tenant-init configuration or the local disk in this
package. Production restoration, application cutover and backup enablement stay
behind their own gates below.

## Restore rehearsal gate

Before any production switch, I test the reviewed private operator-run
capture/import helper against synthetic credentials and an isolated PostgreSQL
instance. Preparing that tooling does not perform a production import. It must
enforce these contracts and stop on a mismatch:

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
  restore client and analyze after restoration. Capture deliberately uses the
  matching source-major/minor client already in the source pod; the helper
  records/checks its version. I test that exact same-major export/restore pair
  before accepting this exception. Never use `--clean` against the source.
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

The rehearsal establishes SQL restore behavior. I time the final import and outage
explicitly in the later cutover procedure. This refresh preserves the rehearsal
copy in its original directory; acceptance requires the retained-data checks above.
No source reset or implicit database replacement is part of the procedure.

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

Authentik preparation does not complete OPS-2. Next come the authorized final
refresh and Authentik cutover/backup/soak, then n8n with preservation
of its encryption key, PVC, published workflows, credentials and natural
schedules. Sure/Plane recovery retention remains coordinated with OPS-66/OPS-7.
The shared instance cannot be retired just because those apps have no pods.

Only after every tenant has a validated destination or separately accepted
retirement can I prepare source StatefulSet/PV/node-local disk removal. Retain
final database and globals backups outside rotation, verify all references and
backup manifests, and run clean Terraform validation. That destructive change
requires separate explicit authorization and its own storage rollback limits.

## Validation boundaries

The original administrator ciphertext passed constrained SOPS MAC/decryption,
identity/key-shape and recipient checks. The complete activation graph rendered
14 resources; all 13 built-in resources including both Secrets passed strict
schemas. This refresh preserves both ciphertexts, the generator and Kustomization
byte for byte. All 12 current nonsecret resources render and pass server dry-run
admission; their 11 built-in resources pass strict schemas with no skips. The
private task record holds live preflight evidence and remaining rollout gates.

The backup shell's synthetic tests cover complete publication, private artifact
modes, relative manifest paths and checksums, current-protected seven-run
retention, and preservation of the previous generation when globals export,
completion-trailer, role coverage, dump or archive validation fails. The private
provisioning helper uses mocked SOPS and synthetic passwords in its dedicated
tests. These checks establish neither actual restore nor runtime performance.
Post-refresh identity, storage, readiness, fresh bootstrap and retained-rehearsal
checks remain required before claiming refresh complete. Production restore and application cutover
retain their separate acceptance gates.
