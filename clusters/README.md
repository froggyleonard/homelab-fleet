# clusters

ArgoCD-reconciled manifests. The hub on cluster-infra watches this directory.

- `infra/bootstrap/` — the only thing applied by hand, once. Fresh-cluster order
  matters: the namespace must exist before the secret, the AppProject CRD must
  be established before the projects, and the projects before root:
  1. `kubectl apply -f clusters/infra/bootstrap/argocd/namespace.yaml`
  2. `kubectl -n argocd create secret generic sops-age
     --from-file=keys.txt=<cluster age private key>`
  3. `kubectl apply -k clusters/infra/bootstrap/argocd/`
  4. `kubectl wait --for=condition=Established
     crd/appprojects.argoproj.io --timeout=120s`
  5. `kubectl apply -f clusters/infra/apps/projects/` — AppProjects, including
     root's own; skipping this wedges root on a nonexistent project
  6. `kubectl apply -f clusters/infra/bootstrap/root-app.yaml`
  Everything after that is GitOps.
- `infra/platform/` — cert-manager, monitoring, Cilium config, kube-vip
- `apps/bootstrap/` — spoke registration (cluster secret, SOPS-encrypted)
- `apps/platform/` — Longhorn, Traefik, cert-manager, NetworkPolicy baseline
- `apps/workloads/` — one directory per service (added in P6):
  authentik, postgres, n8n, sure, ollama, homarr, cloudflared

Conventions: IngressRoute CRDs only; images pinned to version tags; files ordered
`XX-name.yaml` per namespace; `app.kubernetes.io/{name,part-of,managed-by}` labels
on every resource; Secrets only as `*.sops.yaml` (CI enforces).
