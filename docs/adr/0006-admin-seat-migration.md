# 0006 — Admin seat moves to dev-ws1 (key and state residency)

- Status: **accepted** (2026-08-17)
- Deciders: operator (solo)
- Partially supersedes: [0003](0003-sops-age-secrets.md) (key-residency clause);
  0003's decision otherwise stands.

## Context and problem statement

ADR 0003 fixed age-key residency as "my admin workstation plus one offline
backup". That workstation — a desktop that is also a daily driver — is retiring
from the admin/orchestration role; the seat moves to `dev-ws1` (VMID 220), the
always-on dev VM on the user VLAN. Terraform state has the same problem in a
different file: it was desktop-local by doctrine (state is local and gitignored;
remote state is a deliberate non-goal for a solo operator), so the seat move has
to relocate it without forking it.

## Considered options

1. **Keys/state stay on the desktop, seat operates remotely against them** —
   rejected: keeps the retired machine in every critical path and makes the
   "admin workstation" a fiction.
2. **Remote terraform state backend** — rejected: in-cluster options (a
   chart-bundled MinIO, a Kubernetes Secret backend) store the state inside the
   infrastructure the state rebuilds — the same circularity 0003 rejected
   sealed-secrets for; hosted options move real network identity off-lab.
   Locking/sharing/CI benefits all target multi-operator setups this fleet
   doesn't have.
3. **Residency follows the seat; one-time verified moves** — accepted.

## Decision

The admin seat is `dev-ws1`. Residency rules, restated:

- **Both age identities** (cluster + infra) live on the admin seat at
  `~/.config/sops/age/` (0700/0600) **plus the one offline backup**. The
  desktop retains nothing after the migration gates close. The infra identity
  is never auto-loaded — decryption of infra secrets stays an explicit
  `SOPS_AGE_KEY_FILE` action.
- **Terraform state stays local and gitignored**, now on the seat. The move is
  verified end-to-end: zero-diff plan before and after, checksum- and
  serial/lineage-matched, migrated on the same terraform version that wrote it,
  with the superseded desktop copy tombstone-renamed the moment the copy is
  verified so the lineage can never fork.
- **`.terraform.lock.hcl` is committed** from this migration on (checksums and
  selections only — no secrets). The provider constraint (`~> 0.66`) carries no
  cross-minor compatibility promise; the lockfile is what makes rebuilds and
  future seat moves reproduce the exact provider build.
- **Recovery package:** after every apply, `terraform state pull` is snapshotted
  to the offline medium. The offline key backup is verified by decrypting test
  fixtures with both identities *read from the medium itself* before the old
  seat's keys are destroyed. No unencrypted VM backup may contain key material.

### Threat delta (vs. 0003's desktop residency)

Honest accounting of what changes: the seat is an always-on, remotely reachable
VM, so the exposure window is continuous rather than desktop-uptime; a
hypervisor/console compromise now reaches the keys; and both identities plus the
infrastructure credentials they decrypt share one failure domain. Compensations:
key-only socket-activated sshd with a hardening drop-in, overlay-network device
identity with IdP MFA in front of remote access, unattended security upgrades,
and no browser/daily-driver attack surface — the last is surface *reduction*,
not a substitute for offline residency, which is why the offline backup remains
the recovery root.

### Transition note (external secrets)

The successor architecture 0003 deferred — **external-secrets + OpenBao, with
rotation** — is now planned (its design is a separate task and will get its own
ADR). Under it, SOPS+age *narrows* rather than disappears: it remains the
bootstrap root of trust. Invariant carried forward from `.sops.yaml`: any
OpenBao unseal/recovery or initial administrative material is encrypted
**exclusively to the infra identity** — never rendered through KSOPS, never
readable by the cluster recipient. A repo-server compromise must stay a cluster
problem.

## Consequences

- Disaster recovery is still "this repo + keys": repo (public, clean), offline
  key backup, offline state snapshots. The desktop is no longer load-bearing.
- Every future seat migration has a template: move → prove (zero-diff,
  checksums, both-identity decrypt) → only then destroy the old copies, gated.
- The lockfile commit slightly enlarges the public surface (provider names,
  versions, hashes) — reviewed and accepted; it contains no secrets.
