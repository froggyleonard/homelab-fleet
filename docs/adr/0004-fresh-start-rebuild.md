# 0004 — Fresh-start rebuild: no data migration

- Status: **accepted** (2026-07-17)
- Deciders: operator (solo)

## Context and problem statement

Replacing the estate wholesale (ADR 0001, 0002) posed the question of what data
crosses over. A measured inventory showed almost nothing worth the machinery of
migration: n8n held 25 workflows and zero stored credentials; Sure repopulates
from SimpleFIN sync; Ollama models are re-pullable; Vaultwarden held 9 personal
ciphers. Migration tooling (PVC copies, database restores into new-major
versions) would have been built for data that is cheaper to re-create.

## Considered options

1. **Migrate** — dump/restore PostgreSQL tenants and copy PVCs into the new
   clusters; carries old schema and config drift into a fleet meant to be clean.
2. **Fresh start with targeted exports** — re-deploy everything from git, export
   the few irreplaceable items by hand first.

## Decision

Option 2. No data is migrated. Safeguards, in order:

- **P0 (before anything):** I export the Vaultwarden ciphers via the web UI
  (the file stays on my workstation; password-manager replacement is a separate task).
- **P4 staged teardown:** I stop the old VMs first (rollback = start), do a
  last-chance data check to re-confirm the exports, and only then destroy them
  (no rollback — explicitly accepted).
- Everything else is a **fresh install** per the plan's disposition table:
  Traefik/cert-manager/cloudflared, Authentik (providers reconfigured by hand),
  shared PostgreSQL with tenants exactly `authentik, n8n, sure`, n8n, Sure,
  Ollama, Homarr. Not redeployed: Vaultwarden (EOL here), Guacamole (Tailscale
  already covers admin remote access), the Firefly stack (superseded by Sure),
  MetalLB (replaced by Cilium LB-IPAM).

## Consequences

- The new fleet starts with zero configuration drift; everything it runs is
  reconstructable from this repo (plus the age key, ADR 0003).
- Accepted losses: n8n workflows are rebuilt incrementally; Authentik is
  reconfigured manually; historical Sure data before the SimpleFIN window is
  gone.
- The destroy step is irreversible by design; the staged stop-check-destroy
  sequence is the control, not backups of the old estate.
- Going forward the standing data-protection line is the nightly `pg_dump`
  CronJob to the HDD pool — the old cluster's "no backups" posture does not
  carry over.
