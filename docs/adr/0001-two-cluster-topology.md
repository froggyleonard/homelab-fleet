# 0001 — Two-cluster topology on a single node (RKE2 infra + k3s apps)

- Status: **accepted** (2026-07-17)
- Deciders: operator (solo)

## Context and problem statement

The previous estate was a single k3s cluster of four VMs — one node per household
VLAN, workloads pinned with `nodeSelector` — on one Proxmox VE node (Dell R620,
48 threads, 128 GiB RAM, SSD mirror + HDD raidz1). The rebuild had three goals:
a production-representative control plane, GitOps-first management, and a real
blast-radius boundary between the platform layer and the workloads it manages.
Hard constraints: one physical node, no new hardware, and RAM/SSD budgets shared
with training VMs that stay.

## Considered options

1. **Single k3s cluster again** — least overhead, but platform and workloads share
   one failure and upgrade domain, and none of it exercises prod-grade tooling.
2. **Two clusters: RKE2 infra + k3s apps** — separation where it pays, lightweight
   where it doesn't.
3. **Three clusters (infra / apps / lab)** — a dedicated lab cluster exceeded the
   RAM and SSD budget for marginal value; lab needs are already covered by the
   standalone CKA training VMs outside the fleet.

## Decision

Option 2.

- **cluster-infra** — RKE2, 3× control-plane (VMs 201–203), API served by a
  kube-vip ARP VIP (`xx.xx.100.10`). Runs the ArgoCD hub, KSOPS, and
  kube-prometheus-stack. Stateless apart from ArgoCD/monitoring.
- **cluster-apps** — k3s, 1 control-plane tainted `NoSchedule` (VM 211) + 2 workers
  (VMs 212–213). Runs all application workloads, Longhorn (HDD-pool disks), and
  the shared PostgreSQL (dedicated SSD volume on w1).

RKE2 on infra buys the CIS-hardened, prod-representative distro where the control
plane matters; k3s on apps keeps the resident-RAM ceiling at ~50 GiB. ArgoCD on
infra manages both clusters hub-and-spoke (app-of-apps + ApplicationSets).

## Consequences

- Platform upgrades (ArgoCD, monitoring, RKE2 itself) no longer risk workloads,
  and vice versa.
- The 3-node control plane is HA at the VM/OS layer only — everything sits on one
  physical node, so hardware failure takes the fleet. I accept this: the mitigation
  is GitOps + SOPS (rebuild-from-repo), not hardware redundancy.
- More moving parts than one cluster: two CNI installs, two upgrade tracks, spoke
  registration.
- SSD capacity is thin-provisioned with overcommit; I direct growth off the SSD
  pool (Longhorn + backups on HDD). I enforce a hard ≤80% SSD usage checkpoint
  before deploying anything new, until a Prometheus alert takes over.
