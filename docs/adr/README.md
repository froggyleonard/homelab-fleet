# Architecture Decision Records

MADR format. Index:

| # | Title | Status |
|---|---|---|
| [0001](0001-two-cluster-topology.md) | Two-cluster topology on a single node (RKE2 infra + k3s apps) | accepted |
| [0002](0002-cluster-boundary-segmentation.md) | Cluster-boundary segmentation replaces per-workload VLANs | accepted |
| [0003](0003-sops-age-secrets.md) | SOPS+age in-repo as canonical secret store | accepted |
| [0004](0004-fresh-start-rebuild.md) | Fresh-start rebuild — no data migration | accepted |

Cross-cutting: [Zero Trust Architecture](zero-trust/README.md) — how the
decisions above compose into the fleet's trust model, with per-pillar status.
