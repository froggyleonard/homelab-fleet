# 0002 — Cluster-boundary segmentation replaces per-workload VLANs

- Status: **accepted** (task-005 v1 rounds 1–3, convergence 2026-07-14; carried
  unchanged into plan v2)
- Deciders: operator, with two-model consensus review

## Context and problem statement

The previous model segmented *workloads* at L2: one k3s node VM per household
VLAN (DMZ, General, IOT, …), workloads pinned to "their" VLAN with
`nodeSelector`, and a MetalLB VIP in the DMZ for ingress. In practice this
meant VM sprawl, rigid scheduling, a "public-facing" DMZ role that Cloudflare
Tunnel had already made unnecessary, and — the real defect — trust decided by
which subnet a packet came from, with no east-west control inside the cluster
at all.

## Considered options

1. **Keep per-workload VLANs** — familiar, but scales by adding VMs, and offers
   zero intra-cluster isolation.
2. **Cluster-boundary VLANs + in-cluster NetworkPolicies** — segmentation moves
   to the layer that can see workload identity.

## Decision

Option 2. Each cluster lives on exactly one dedicated VLAN: infra = 100
(`xx.xx.100.0/24`), apps = 110 (`xx.xx.110.0/24`).

- **North-south** — OPNsense inter-VLAN matrix, default deny:
  - MGMT → 100/110 (admin)
  - 100 → 110 restricted to ArgoCD (6443/443) + monitoring scrape
  - 110 → 100 deny
  - household VLANs → published LB VIPs :443 only
  - IOT / Guest / IPCAM → deny
- **East-west** — Cilium NetworkPolicies per namespace, default-deny baseline on
  cluster-apps; each service's policies ship with its manifests, so a service
  without policies doesn't reach anything.
- **Inbound public** — Cloudflare Tunnel only (`cloudflared` dials out; zero
  inbound port-forwards). No VLAN carries a "public-facing" role anymore; the
  old DMZ VLAN keeps serving its standalone hosts but receives nothing new.

## Consequences

- Workload isolation is now identity-based (namespace/label selectors) instead of
  location-based (subnet) — finer-grained, and it moves with the workload.
- The cost is policy discipline: every new service must declare its NetworkPolicies
  or it ships dark. This is enforced by convention (policies live beside the
  service manifests) and observed via Hubble flow visibility.
- Household VLANs and their firewall posture are untouched; only the cluster
  VLANs are new.
- Losing per-workload L2 separation was reviewed explicitly (reviewer finding,
  v2 round 1) and accepted: the OPNsense matrix still bounds the clusters, and
  NetworkPolicies replace — and exceed — what node-per-VLAN pinning provided.
