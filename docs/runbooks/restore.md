# Restore runbook

Written to be followed when something is already on fire. Read the triage table,
go to that section, do the steps in order. Background and rationale are in
[ADR 0008](../adr/0008-backup-architecture.md) — not here.

**Conventions in this file.** Addresses are written `xx.xx.30.80` style; this repo
is public, so substitute the real prefix from the private orchestrator repo.
Every command block says **which host it runs on**. Running a hypervisor command
on the admin seat does nothing useful and wastes time you do not have.

---

## Triage — what broke, where to go

| Symptom | Layer | Section |
|---|---|---|
| One app's data is wrong, deleted or corrupted | L2 | [A. Restore one database](#a-restore-one-database) |
| One VM or container is broken, but the node is fine | L3 | [B. Restore one guest](#b-restore-one-guest) |
| A workload's manifests are wrong | L1 | Revert in this repo; ArgoCD syncs it |
| Home Assistant is broken | L4 | [C. Restore Home Assistant](#c-restore-home-assistant) |
| The node is gone — hardware, fire, theft | L4 | [D. Total loss](#d-total-loss) |
| "Is the backup even working?" | — | [E. Health check](#e-health-check) |

**Before you restore anything:** take a snapshot or a fresh dump of the current
broken state first, if you still can. A bad restore on top of a bad state leaves
you with nothing to compare against.

---

## A. Restore one database

The nightly dumps live on the admin seat under `~/backups/pg/current/` — a
symlink to the newest **complete** run. Never read the run directories directly;
the symlink is the only thing that guarantees you get a finished set.

Each instance has two files: `<name>.dump` (custom format) and
`<name>-globals.sql` (roles, **including password hashes**).

```bash
# ON THE SEAT — confirm which run you are about to trust
ls -l ~/backups/pg/current/
cat ~/backups/pg/current/MANIFEST      # run id, artifact count, sizes
```

If the target instance is a fresh/empty one, **restore globals first** — the
database dump's grants reference roles that only exist in the globals file:

```bash
# ON THE SEAT — globals are plain SQL, so psql, not pg_restore
kubectl exec -i -n <ns> <pg-pod> -- \
  psql -v ON_ERROR_STOP=1 -U postgres < ~/backups/pg/current/<name>-globals.sql

kubectl exec -i -n <ns> <pg-pod> -- createdb -U postgres <dbname>

kubectl exec -i -n <ns> <pg-pod> -- \
  pg_restore --exit-on-error -U postgres -d <dbname> < ~/backups/pg/current/<name>.dump
```

**Then check the application's own login role exists and can log in** — not just
that tables came back. That is the exact failure this design was built around:

```bash
# ON THE SEAT
kubectl exec -n <ns> <pg-pod> -- \
  psql -U postgres -tAc "select rolname, rolcanlogin from pg_roles where rolcanlogin"
```

If you are restoring **into the live instance**, drop and recreate the database
rather than restoring over it — a `pg_restore` into a populated database leaves a
hybrid of old and new rows that is worse than either.

---

## B. Restore one guest

Archives are on the hypervisor's HDD pool under the `pve-backups` storage.

```bash
# ON THE HYPERVISOR (root)
ls -lh /Media/backups/dump/ | tail -20        # newest last
```

**Restore to a scratch ID first** whenever the original still exists. Restoring
over a live guest destroys its disks with no undo.

```bash
# ON THE HYPERVISOR (root) — 299 is the scratch ID; the original is untouched
qmrestore /Media/backups/dump/<archive>.vma.zst 299 --start 0
qm set 299 --net0 <model>=<mac>,bridge=<bridge>,link_down=1   # no IP collision
qm start 299
```

Check it reached a login prompt and, for UEFI guests, that `efidisk0` was
recreated (`qm config 299 | grep efidisk`). Then either promote it or destroy it:

```bash
# ON THE HYPERVISOR (root) — READ THE VMID TWICE. Live guests are numbered 2xx.
qm config 299 | head -3        # confirm it is the scratch guest
qm destroy 299 --destroy-unreferenced-disks 1 --purge 1
zfs list -t all | grep -c 299  # expect 0
```

For a container use `pct restore` instead of `qmrestore`; everything else is the
same. Containers are in the nightly set too, and are easy to forget because the
hypervisor lists them separately from VMs.

---

## C. Restore Home Assistant

Home Assistant writes its own native backup daily; the seat fetches the newest
one and it rides into both the local archives and the off-site repository.

```bash
# ON THE SEAT
ls -l ~/backups/haos/
```

Restore it through Home Assistant's own UI (Settings → System → Backups → upload)
rather than restoring the whole VM — the native backup carries the config,
database and add-ons, and comes back onto a working OS instead of replacing one.

If the VM itself is gone, restore the guest first (section B), then apply the
native backup on top for anything newer than the archive.

---

## D. Total loss

The node is gone. **Order matters here, and the first two steps are not optional.**

### D1. Get the credentials — they are NOT in this repo

The off-site repository contains the age keys, so you cannot use anything
encrypted in this repo until after you have opened it. Both credentials live in
three independent places (ADR 0008): the (now gone) hypervisor, the offline
recovery medium, and the password manager. Use one of the surviving two.

You need: the repository URL, the object-store key pair, and the repository
password.

### D2. Open the repository from any machine

```bash
# ON ANY TRUSTED MACHINE — install the pinned restic version, then:
read -rsp 'object-store key id: '     AWS_ACCESS_KEY_ID;     echo
read -rsp 'object-store secret key: ' AWS_SECRET_ACCESS_KEY; echo
read -rsp 'restic repo password: '    RESTIC_PASSWORD;       echo
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY RESTIC_PASSWORD
export RESTIC_REPOSITORY='s3:https://<endpoint>/<bucket>/<path>'

restic snapshots                       # newest last — sanity-check the date
restic restore latest --target /tmp/restore
```

`read -rsp` keeps the values out of your shell history and out of the process
list. Do not put them on a command line.

### D3. Recover the age keys FIRST

```bash
# ON THE RESTORE MACHINE
install -D -m 0600 /tmp/restore/Media/backup-staging/seat/age/keys.txt \
  ~/.config/sops/age/keys.txt
sops -d <any-encrypted-file-in-this-repo> | head -1   # prove decrypt works
```

Until this works, every secret in this repo is unusable. Do it before you start
rebuilding anything.

### D4. Rebuild the platform

1. **Hypervisor** — reinstall, recreate the pools and the storage definitions.
   `/etc/pve` from the restore is your reference for what existed:
   `ls /tmp/restore/etc/pve/qemu-server/` lists every guest and its exact config.
   **Read it; do not copy it over a running `/etc/pve`.**
2. **Terraform** — the state is in the restore at
   `…/seat/terraform/terraform.tfstate`. Put it back before running any plan, or
   Terraform will propose to create everything that already exists.
3. **Clusters** — rebuild from this repo (L1). ArgoCD reconciles the workloads.
4. **Databases** — restore each instance from the dumps in `…/seat/pg/`,
   **globals first**, per section A.
5. **Home Assistant** — section C, from `…/seat/haos/`.

### D5. Re-establish the backups themselves

Do not declare the recovery finished until the pipeline is running again — a
restored fleet with no backups is one incident away from the same morning.
Reinstall the exporter, receiver and timers, then run one push by hand and
confirm a new snapshot appears.

---

## E. Health check

```bash
# ON THE SEAT — did the dumps and the HA fetch run?
systemctl --user list-timers --all
ls -l ~/backups/pg/current/ ~/backups/haos/
tail -20 ~/backups/offsite-push.log
```

```bash
# ON THE HYPERVISOR (root) — did the archives and the off-site copy run?
ls -lh /Media/backups/dump/ | tail -5
systemctl status backup-verify.timer 'restic-check@*.timer'
set -a; . /etc/restic/b2.env; set +a
restic snapshots | tail -5
```

Three things are worth checking by eye rather than trusting:

1. **Dates, not just presence.** A stale file is the failure mode this design
   cannot alert on by itself.
2. **The dump set is complete** — `MANIFEST` declares a count; count the files.
3. **The newest off-site snapshot lists both paths** (the staged seat set *and*
   the hypervisor config), not just one.

Notification is **failure-triggered only**. Silence is not evidence of health.
