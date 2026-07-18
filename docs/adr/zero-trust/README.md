# Zero Trust Architecture

How zero-trust principles are implemented across this fleet. This is not a
single decision record — it is the cross-cutting view that ties the numbered
ADRs together and states, honestly, which pillars are deployed by the rebuild
and which are hardening layered on top of it. Phase references (P1–P7) follow
the rebuild sequence in the repo README.

## Principles

Working definition (after NIST SP 800-207):

1. **Network location confers no trust.** Being on an internal VLAN, or inside a
   cluster, authorizes nothing by itself.
2. **Every access is authenticated and authorized** against identity — user,
   device, or workload — not source address.
3. **Least privilege everywhere:** default-deny at every boundary; each allowed
   flow is explicit and reviewable in git.
4. **Assume breach:** minimize blast radius, make state reconstructable, watch
   the flows.

## Architecture by pillar

| Pillar | Mechanism | Status |
|---|---|---|
| North-south segmentation | OPNsense default-deny inter-VLAN matrix ([ADR 0002](../0002-cluster-boundary-segmentation.md)) | applied in P1 |
| Public exposure | Cloudflare Tunnel only — egress-out, zero inbound port-forwards | model carried over; re-pointed in P6 |
| Admin & device access | Tailscale (WireGuard, device identity, MFA via IdP); Guacamole retired | in place |
| East-west microsegmentation | Cilium NetworkPolicies, default-deny baseline on cluster-apps; policies ship with each service ([ADR 0002](../0002-cluster-boundary-segmentation.md)) | deploys P5–P6 |
| User identity at the edge | Authentik (OIDC/SSO) behind Traefik | Authentik deploys in P6; uniform forward-auth is post-rebuild hardening (below) |
| Workload identity / mTLS | Cilium mutual authentication | post-rebuild hardening (below) |
| Secrets | SOPS+age in-repo, KSOPS render in ArgoCD; age key never on nodes ([ADR 0003](../0003-sops-age-secrets.md)) | in place from P2 |
| Host & cluster hardening | Ansible common-hardening role; RKE2 CIS profile (protect-kernel-defaults, dedicated etcd user, PSA labels) | applied P2–P3 |
| Visibility | Hubble flow observability on both clusters; kube-prometheus-stack (short-retention until fleet stabilizes) | deploys P3/P5 |
| Recoverability | GitOps-first: fleet reconstructable from this repo + one age key ([ADR 0001](../0001-two-cluster-topology.md), [ADR 0004](../0004-fresh-start-rebuild.md)); nightly `pg_dump` → HDD pool | in place at P6 |

## How a request is trusted

**A person opening a service** (from a household VLAN or the internet):
traffic reaches the cluster only through a published LB VIP :443 or the
Cloudflare Tunnel — the OPNsense matrix and the absence of port-forwards permit
nothing else. TLS terminates at Traefik (cert-manager); Authentik authenticates
the user before the app does its own authorization.

**An admin:** joins the tailnet (device identity + IdP MFA), reaches MGMT-side
resources through Tailscale subnet routes. No firewall holes are ever opened
from user VLANs for admin convenience; the Guacamole browser gateway was
retired rather than carried as a second credential surface.

**A workload calling another workload:** starts from default-deny. The call
succeeds only if the target service's NetworkPolicies — versioned beside its
manifests — explicitly allow that namespace/label identity. Cross-cluster,
only ArgoCD (6443/443) and monitoring scrape are permitted from infra to apps;
apps → infra is denied entirely.

**A change to the fleet itself:** lands via git commit → ArgoCD reconciliation.
Secrets decrypt only inside ArgoCD via KSOPS; CI (gitleaks, kubeconform,
lint/validate) gates every push.

## Post-rebuild hardening (planned, in order)

These complete the architecture once the rebuild's service phase is done. Each
layers onto a component the rebuild already deploys — none requires new
infrastructure:

1. **Uniform policy enforcement at ingress** — Authentik forward-auth middleware
   on every Traefik IngressRoute, so no request reaches any app unauthenticated
   regardless of source VLAN. Replaces the old model of per-app OIDC opt-in and
   IP-allowlist middleware.
2. **Workload mTLS** — Cilium mutual authentication + transparent encryption for
   east-west traffic, moving workload identity from labels to cryptographic
   identity.
3. **Authn/authz audit trail** — Authentik events, Hubble policy-verdict flows,
   and API-server audit logs shipped to one queryable place; "assume breach"
   only means something if access decisions are recorded.

## Known gaps

Stated so this document doesn't overclaim:

- No continuous verification / device-posture evaluation — Tailscale ACLs are
  static; trust is evaluated at connect, not per-request.
- Metrics and (until item 3 lands) logs are short-retention; forensics depth is
  limited.
- Everything runs on one physical node ([ADR 0001](../0001-two-cluster-topology.md)):
  availability is out of scope for this architecture; confidentiality and
  integrity are what these controls defend.
