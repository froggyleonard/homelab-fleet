# clusters

ArgoCD-reconciled manifests. The hub on cluster-infra watches this directory.

- `infra/bootstrap/` — the only thing applied by hand, once: ArgoCD + KSOPS + the
  root Application. Everything after that is GitOps.
- `infra/platform/` — cert-manager, monitoring, Cilium config, kube-vip
- `apps/bootstrap/` — spoke registration (cluster secret, SOPS-encrypted)
- `apps/platform/` — Longhorn, Traefik, cert-manager, NetworkPolicy baseline
- `apps/workloads/` — one directory per service (added in P6):
  authentik, postgres, n8n, sure, ollama, homarr, cloudflared

Conventions: IngressRoute CRDs only; images pinned to version tags; files ordered
`XX-name.yaml` per namespace; `app.kubernetes.io/{name,part-of,managed-by}` labels
on every resource; Secrets only as `*.sops.yaml` (CI enforces).
