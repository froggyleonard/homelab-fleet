# Sequential recovery rehearsal

I prepared one isolated recovery stage at a time: a read-only file-volume
inspection, a PostgreSQL 18 restore and a PostgreSQL 16 restore. Every stage
retains two replicas and allocates at most 5 GiB per storage worker. The child
Application starts at `00-idle` and has no automatic sync policy.

The [runbook](../../../../docs/runbooks/ops45-recovery-rehearsal.md) describes
source binding, explicit stage transitions, acceptance and scratch cleanup.
The [stage inventory](../../../../docs/runbooks/ops45-rehearsal-stages.json)
lists the exact names and paths for the private preflight tooling. Preparation
does not establish successful recovery or authorize a deployment or deletion.
