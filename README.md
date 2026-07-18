# homelab-fleet

GitOps monorepo for a two-cluster Kubernetes fleet on a single Proxmox VE node
(Dell R620). Provisioned with Terraform + Ansible, reconciled by ArgoCD, secrets
encrypted in-repo with SOPS + age.

## Topology

| Cluster | Distro | Nodes | VLAN | Purpose |
|---|---|---|---|---|
| **cluster-infra** | RKE2 (HA) | 3× control-plane | 100 (xx.xx.100.0/24) | ArgoCD hub, platform services, monitoring |
| **cluster-apps** | k3s | 1× CP (tainted) + 2× workers | 110 (xx.xx.110.0/24) | Application workloads, Longhorn storage |

- **CNI:** Cilium on both clusters (kube-proxy replacement, Hubble, LB-IPAM — no MetalLB)
- **API HA:** kube-vip (ARP) on cluster-infra — VIP `xx.xx.100.10`
- **GitOps:** ArgoCD hub on cluster-infra manages both clusters (app-of-apps + ApplicationSets)
- **Secrets:** SOPS + age, rendered by KSOPS inside ArgoCD — every secret in this repo is encrypted at rest
- **Storage:** SSD mirror for OS/etcd/PostgreSQL; HDD raidz1 pool for Longhorn volumes and backups
- **Ingress:** Traefik (IngressRoute CRDs only) behind Cilium LB-IPAM VIPs; public exposure via Cloudflare Tunnel only — zero inbound port-forwards

## Repository layout

```
terraform/     VM provisioning (bpg/proxmox): cloud-init template + fleet definition
ansible/       Node configuration: common hardening, RKE2 servers, k3s
clusters/
  infra/       ArgoCD bootstrap + platform apps for cluster-infra
  apps/        Platform + workload apps for cluster-apps (deployed via the hub)
docs/adr/      Architecture Decision Records (MADR)
```

## Bootstrap order

1. `terraform/envs/pve` — template 9000 (Ubuntu 24.04 cloud-init) + 6 fleet VMs
2. `ansible/` — hardening → RKE2 HA on 201–203 → k3s on 211–213
3. `clusters/infra/bootstrap` — ArgoCD + KSOPS, then the root app takes over
4. cluster-apps registered as a spoke; everything else reconciles from this repo

## Guardrails

- CI validates every push: gitleaks, `terraform fmt`/`validate`, ansible-lint, kubeconform
- No Terraform state, kubeconfigs, or plaintext secrets are ever committed
- History is clean by construction — this repo was born public
