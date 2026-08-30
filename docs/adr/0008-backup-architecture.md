# 0008 — Backup architecture: four layers, and only the irreplaceable set goes off-site

- Status: **accepted** (2026-08-29)
- Deciders: operator (solo)

## Context and problem statement

There was no backup job on the hypervisor at all. Not a misconfigured one — none.
The clusters are rebuildable from this repo, which had quietly become the excuse
for not looking any harder, but the things GitOps *cannot* rebuild were sitting on
exactly one pool in exactly one building:

- application PostgreSQL data (Mealie, SparkyFitness, Matrix/Synapse, MAS),
- the Terraform state for the whole fleet,
- the **age private keys** that decrypt every SOPS secret in this repo,
- Home Assistant's configuration and history,
- `/etc/pve` — the VM definitions, storage and firewall config.

A disk failure loses the first four. A fire, a flood or a theft loses everything,
including the ability to *use* this repo, because without the age keys the
encrypted secrets in it are noise.

Two constraints shaped the answer. I run **one node** — no cluster, no HA, no
second machine to replicate to. And backups that only exist on that node are not
backups.

## Considered options

1. **vzdump only, to local storage.** Cheap, and it covers the whole-VM restore
   case well. Useless against fire/theft/flood, and it does not help at all with
   "one database got corrupted" — restoring a 12 GiB VM archive to recover a
   400 KB dump is the wrong instrument.
2. **Proxmox Backup Server.** The right answer with a second machine to run it on.
   I do not have one, and running PBS on the node it protects buys nothing.
3. **Full VM archives, off-site.** Simple to reason about, and unaffordable:
   tens of GiB nightly over a residential uplink, to pay for storing operating
   systems this repo already describes.
4. **Layered: rebuildable things stay rebuildable; the irreplaceable set goes
   off-site.** More moving parts, and each layer has to be *proved* rather than
   assumed.

## Decision

**Option 4 — four layers, each with a different job.**

| Layer | What it protects | Where it runs | Cadence |
|-------|------------------|---------------|---------|
| L1 | Cluster and workload definitions | this repo, GitOps | every commit |
| L2 | Per-app PostgreSQL dumps + **globals** | admin seat, `kubectl exec` | nightly |
| L3 | Whole-guest `vzdump` archives | hypervisor → HDD pool | nightly |
| L4 | The irreplaceable set, encrypted, **off-site** | hypervisor → Backblaze B2 via restic | nightly |

L2 lands on the admin seat, which L3 then sweeps up, which means the database
dumps ride into both the local archive and the off-site repository without any
extra plumbing. The layers are chained on purpose; they are not four independent
jobs that happen to run at night.

### What is deliberately NOT backed up

- **Longhorn data disks** on the two worker VMs, excluded at the disk level.
  They are replicated block storage for rebuildable workloads; including them
  turned a ~38 GiB nightly job into a multi-terabyte one.
- **Operating systems, container images, cluster state.** L1 rebuilds them.
- **Training VMs and the cloud-init template.**

Writing this list down is part of the decision. An unstated omission is
indistinguishable from an oversight six months later.

### The globals rule

**Every `pg_dump` is accompanied by `pg_dumpall --globals-only`.**

A custom-format `pg_dump` contains no role definitions. Restore one into a fresh
instance and you get a database whose grants reference roles that do not exist,
and an application that cannot log in — the dump looks perfect and the restore is
useless. One of our instances has a second, non-superuser login role that exists
*only* in the globals; the CronJob deployed at the time captured neither.

This is not theoretical here: the failure was reproduced against a fresh cluster
(`role "…" does not exist`, application role missing entirely), then the fix was
proved against the same fresh cluster. Globals files carry SCRAM password hashes,
so they are secret-bearing and are handled like the dumps themselves.

### The root-of-trust rule

**The off-site repository contains the age keys.** Therefore the credentials
needed to open that repository must be recoverable *without* the age keys, or the
backup is unrecoverable in precisely the disaster it exists for.

The requirement is that these two values survive any single event that destroys
the hypervisor, **including one that destroys the building it is in**. A restore
rehearsal that authenticates from the operational copy on the hypervisor proves
nothing about this, so the rehearsal must use an out-of-band copy.

**Today that requirement is not met, and this ADR records it rather than
implying otherwise.** The values exist on the hypervisor (operational) and on
the offline recovery medium (ADR 0006). Both are in the same building. There is
no third, off-premises copy — an earlier draft of this plan named a password
manager as the third place, which was an assumption about my setup rather than a
fact about it; I do not use one, by choice.

Note what does *not* fix this. A secrets manager (OpenBao, planned separately)
cannot hold this credential — the backup job is a systemd unit on the hypervisor,
outside both clusters — and its own unseal and recovery keys would need exactly
the same treatment. Software does not create a place to keep a root secret; it
creates another root secret that needs one. The answer is a physical copy
somewhere else, and it is small: two values and a URL.

### Direction of transfer

**The admin seat pushes to the hypervisor; the hypervisor never reaches into the
seat.** The seat holds no repository password and no object-store credentials, so
compromising the seat cannot read, alter or delete backup history. It can offer
the hypervisor a stream — which is validated as hostile input (spooled under a
size cap, every archive member checked for name, type and link target, extracted
as an unprivileged user, never root) before anything touches the repository.

The original design had the hypervisor pull, for the same isolation reason. The
firewall settled it: the management VLAN's egress rules permit only intra-VLAN
traffic, four TCP ports to anywhere, and non-RFC1918 destinations. SSH into the
user VLAN is not among them, and the hypervisor is not a tailnet node. The seat's
route to it runs over the tailnet, which is the admin path this network already
mandates — so pushing needed **no firewall change**, while preserving the pull
would have required punching the exact hole the segmentation exists to prevent.

### Verification, because an unverified backup is a rumour

- **Restore rehearsals are part of "done", not a follow-up.** A guest was
  restored to a scratch ID and booted (the UEFI case, chosen because it is the
  most likely to come back unbootable), then destroyed. Both databases were
  restored into a genuinely fresh PostgreSQL cluster.
- **Freshness assertions** run on the hypervisor each morning: every artifact
  class must be younger than its expected interval. This is what catches a
  producer that has quietly stopped.
- **Repository integrity** is checked on a schedule, including a read-data
  sample, so silent corruption surfaces before a restore needs it.
- **Failures notify** into Matrix #alerts (ADR 0007).

## Consequences

**Good**

- The irreplaceable set exists in three places, one of them off-site and
  client-side encrypted, for a few dollars a month.
- A single-database mistake is now a small, fast restore rather than a whole-VM
  rollback.
- The globals gap is closed everywhere, including in a job that was already
  deployed with the defect.
- Every layer has been exercised at least once, on real data.

**Bad, and accepted**

- **No dead-man switch.** Notification is failure-triggered, so a dead
  hypervisor, a disabled timer or a broken notification path produces silence,
  not an alert. The compensating control is the morning freshness check; the
  revisit trigger is a second node or a monitoring stack.
- **Two clocks.** The seat runs UTC while the hypervisor and Home Assistant run
  local time, and the pipeline has a required order. Every seat timer that must
  order against them is written with an explicit timezone. A bare `OnCalendar`
  here means UTC and would silently ship stale-but-plausible data.
- **The seat can initiate.** Under the abandoned pull design it could only wait
  to be asked. The validation on the receiving side is now the whole boundary.
- **Retention costs storage.** 7 daily / 4 weekly / 3 monthly locally under a
  hard quota; 7/4/6 off-site with pruning enabled.
- **No off-premises copy of the repository credentials yet** (see the
  root-of-trust rule). The off-site backup is complete and correct, and a fire
  that takes the building currently takes the ability to open it. This is the
  largest remaining hole in the design and it is a physical errand, not an
  engineering task.

## Related

- ADR 0003 — SOPS+age secrets (why the age keys are the crown jewels)
- ADR 0006 — admin seat migration (the offline recovery medium)
- ADR 0007 — Matrix notification backbone (where failures land)
- `docs/runbooks/restore.md` — the procedure this architecture exists to enable
