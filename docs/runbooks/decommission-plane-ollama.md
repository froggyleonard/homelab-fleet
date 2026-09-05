# Plane and Ollama retirement

I am retiring Plane after the Tempo cutover and removing unused Ollama for
Talos preflight. This is the first retirement stage. Merging deploys through
ArgoCD auto-sync/prune and requires my explicit approval.

## Effect of this change

| Component | Removed by reconciliation | Retained |
| --- | --- | --- |
| Plane | Seven Deployments, three StatefulSets, two Jobs, eight Services, chart ServiceAccount, two ConfigMaps, IngressRoute and Middleware | Namespace, encrypted secrets, policies, shared PostgreSQL database/role, three PVCs totaling 12 GiB |
| Ollama | Deployment, Service, 60 GiB PVC and exclusive `longhorn-single` StorageClass | Namespace/policies and Application for observed pruning; existing remote backups |
| n8n | `OLLAMA_BASE_URL` and the Ollama TCP/11434 egress rule | Published workflows and every other integration |

The n8n environment change rolls its single Deployment; account for brief UI,
webhook and scheduler interruption. Sure retirement is a separate change gated
on the MoneyMatter workflow cutover. No shared database objects are dropped.

## Why Applications remain

The live Applications have no resource-deletion finalizers. Removing only
Application files would orphan their workloads. I keep them reconciling:
Ollama retains its namespace/policies; Plane switches from the Helm chart to a
non-empty retirement-marker Kustomization. `plane-config` retains separate
ownership of recovery resources. No allow-empty setting or broad diff ignore
is needed. See [ArgoCD deletion](https://argo-cd.readthedocs.io/en/stable/user-guide/app_deletion/)
and [automatic pruning](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/).

All three live Plane StatefulSets report Retain for both deletion and scaling.
Their PVCs have no ownerReferences or Argo tracking annotation and are absent
from the chart Application resource inventory. Recheck these facts immediately
before rollout; stop if any changed. Keeping the namespace is essential.
[Kubernetes PVC retention](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/#persistentvolumeclaim-retention)

## Before approval and rollout

1. Recheck the live Application inventory against the table, confirm no new
   callers, and record the current Git revision. Baseline before preparation:
   `0da386a`. Plane's existing failed sync is the immutable migration Job
   template; the new source removes that Job instead of retrying its update.
2. Confirm no in-flight backup uses either app's volumes. The first Longhorn
   backup run was still active during preparation. Require completed Ollama
   backup coverage and retain its remote backup identity outside rotation;
   do not delete backup objects with the volume. The live Ollama model list
   is empty and its directory uses 48 KiB, containing a recommendation cache
   and identity files. Those files were not opened or copied. Volume deletion
   discards that local identity; restoring it requires the retained backup.
3. Preserve the latest full shared-PostgreSQL archive outside routine retention,
   validate gzip/trailer and record its date. `pg_dumpall` contains globals and
   both database tenants. The checked 2026-09-05 04:00 run passed gzip validation;
   an independent restore is not yet proved. Keep all Plane PVCs and backups.
   Confirm Tempo contains the required migrated work and no new Plane writes
   are expected before stopping Plane. Capture a final database archive after
   writers stop, before later data disposal.
4. Check current Longhorn scheduling and retained app health. Before retirement,
   MoneyMatter and Tempo each lacked a replica because apps-w2 had only about
   63 MiB allocation headroom. Ollama reserves 60 GiB there. Releasing it should
   permit both missing replicas (8 + 5 GiB), but recovery must be observed.
5. Validate the exact PR revision and obtain my explicit merge approval.
   This runbook does not authorize merge, namespace deletion or credential work.

## Observe the authorized rollout

Watch the root revision, then Plane/Ollama/n8n reconciliation. Require:

- No Plane or Ollama workload pods, Services or IngressRoutes. Plane chart
  resources are gone and the retirement marker is Synced/Healthy.
- All three Plane PVCs still Bound with their original PVs; shared PostgreSQL,
  Tempo and retained applications remain healthy.
- Ollama PVC/PV/Longhorn volume and its replica allocation are gone. Check that
  no other claim used `longhorn-single`; it was exclusive in the baseline.
- n8n becomes Ready and retains its published workflows. Check natural scheduled
  runs and webhook health without sending test notifications.
- MoneyMatter and Tempo regain healthy replicas on distinct workers, or record
  the actual remaining scheduling error. Do not declare recovery from capacity
  arithmetic. Backup coverage follows the retained-volume inventory.

Plane's actual usage was one database session during inspection. No published
n8n graph among the six visible workflows referenced Plane or Ollama. This
inspection is a baseline, not proof that every external consumer was found.

## Rollback and later cleanup

Revert the specific retirement commit through GitOps after approval, retaining
all unrelated intervening changes. Plane reuses its original PVCs and shared
DB; the chart's migration Job is recreated after the removed Job is confirmed
absent. Keep the namespace, encrypted secrets and project permissions available.
If database recovery is needed, restore globals before the database into an
isolated instance and validate access before touching production.

Ollama's deleted PVC cannot be restored by Git revert alone. Prepare a PVC
restored from its retained Longhorn backup before restoring its Deployment;
otherwise it starts empty with a new identity. Re-pull models if needed.
No key extraction or regeneration is part of this task.

After successful shutdown and a separately agreed retention/restore gate,
prepare a second GitOps stage to prune residual namespace resources and then
remove Applications and unused AppProject source/destination entries. Never
remove `plane-config`'s namespace while its PVCs are still to be retained.
Shared PG tenant-init/network allow removal, database/role deletion, dashboard
links, DNS/tunnel routes, Authentik objects and seat MCP/credential retirement
need their own concrete cleanup scope. Existing shared backups continue.
