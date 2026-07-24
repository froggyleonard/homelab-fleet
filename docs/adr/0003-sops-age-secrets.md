# 0003 — SOPS + age in-repo as canonical secret store

- Status: **accepted** (2026-07-17)
- Deciders: operator (solo)

## Context and problem statement

The old convention kept `<PLACEHOLDER>` values in manifests with actual secrets
stored in Vaultwarden. Two things broke it: Vaultwarden is not redeployed on the
new fleet (end-of-life here; its replacement is a separate, post-rebuild task),
which severs the bridge between manifests and their real values. In addition,
this repo is public, so any committed secret must be encrypted at rest by
construction, not by care.

## Considered options

1. **sealed-secrets** — encryption key lives in the cluster, which is exactly the
   thing a fresh-start rebuild destroys; poor disaster-recovery fit.
2. **external-secrets + Vault/OpenBao** — the credible long-term architecture, but
   it adds a stateful, availability-critical service to a fleet being built from
   zero. Deferred, not rejected.
3. **SOPS + age, rendered by KSOPS in ArgoCD** — secrets encrypted in-repo, one
   key to protect, no extra runtime service.

## Decision

Option 3. SOPS+age files in this repo are the **canonical store for all platform
secrets** (PostgreSQL passwords, Authentik OIDC, Cloudflare Tunnel token,
SimpleFIN token, …). KSOPS decrypts at render time inside ArgoCD; the
`<PLACEHOLDER>` convention is retired.

Key handling:

- The age private key lives on my admin workstation plus one **offline backup**
  (made during P2). It is never committed to any repo and never present on
  cluster nodes outside the KSOPS decryption secret.
- CI runs gitleaks on every push; GitHub push protection is on; Terraform state
  and kubeconfigs are kept out of the tree entirely.

## Consequences

- Disaster recovery collapses to: this repo + one age key. That is the point.
- Secret changes are audited by git history like everything else.
- The age key is the crown jewel — its loss orphans every secret (hence the
  mandatory offline backup), and its leak compromises them (hence
  workstation-only residency).
- Rotation is manual (re-encrypt + commit); acceptable at this fleet's secret
  count. The migration path to external-secrets + OpenBao stays open and would
  be its own ADR.
