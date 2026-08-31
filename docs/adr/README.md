# Architecture Decision Records

MADR format. Index:

| # | Title | Status |
|---|---|---|
| [0001](0001-two-cluster-topology.md) | Two-cluster topology on a single node (RKE2 infra + k3s apps) | accepted |
| [0002](0002-cluster-boundary-segmentation.md) | Cluster-boundary segmentation replaces per-workload VLANs | accepted |
| [0003](0003-sops-age-secrets.md) | SOPS+age in-repo as canonical secret store | accepted |
| [0004](0004-fresh-start-rebuild.md) | Fresh-start rebuild — no data migration | accepted |
| [0005](0005-plane-task-tracker.md) | Plane CE as the fleet task tracker | accepted |
| [0006](0006-admin-seat-migration.md) | Admin seat moves to dev-ws1 (key and state residency) | accepted |
| [0007](0007-matrix-notification-backbone.md) | Matrix (Synapse) as the notification backbone | accepted |
| [0008](0008-backup-architecture.md) | Backup architecture — four layers, irreplaceable set off-site | accepted |

Runbooks: [restore.md](../runbooks/restore.md) — the recovery procedure
ADR 0008 exists to enable.

Cross-cutting: [Zero Trust Architecture](zero-trust/README.md) — how the
decisions above compose into the fleet's trust model, with per-pillar status.
