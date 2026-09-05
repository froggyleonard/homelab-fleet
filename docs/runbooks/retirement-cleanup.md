# Retired service cleanup

I am cleaning up the remaining configuration after Plane, Ollama and Sure
workload retirement. Each production merge still requires my explicit approval.

## Step 1: drain Ollama and stop retired tenant provisioning

The existing Ollama Application now renders an intentionally empty Kustomization
and explicitly enables `allowEmpty`. Auto-prune removes its namespace and three
NetworkPolicies. Kubernetes also removes the namespace's generated ServiceAccount
and root CA ConfigMap. Before approving, verify no new pods, PVCs, Secrets or
other application data have appeared there. Stop if the inventory has changed.
Keep the Application and its project destination while deletion finishes.

The shared PostgreSQL PostSync hook now manages only Authentik and n8n. Removing
Plane/Sure env references and loop entries prevents their future re-creation
and password/grant maintenance. Their existing databases, roles and encrypted
credential fields remain; this change contains no DROP, revoke or key rotation.
The hook runs again on sync for the two retained tenants using existing values.
The server NetworkPolicy removes Plane/Sure namespace access and preserves
Authentik, n8n, same-namespace jobs and DNS rules.

The unused Plane Helm repository permission is removed. Plane now reads its
retirement marker from the fleet repo; plane-config continues to own recovery
resources. Plane/Sure namespace destinations remain authorized for that purpose.

After the authorized rollout, require an absent Ollama namespace, an empty live
Ollama Application resource list, successful retained-tenant initialization and
healthy PostgreSQL/Authentik/n8n. Confirm Plane/Sure databases and roles still
exist and all three Plane PVCs remain Bound. No workflow is modified here.

## Step 2: unregister the drained Ollama Application

Only after observing step 1 complete, merge the separately prepared follow-up
that removes the empty Kustomization directory, Ollama Application and its
AppProject destination. Do not merge both steps back-to-back: deleting the
Application before it prunes would orphan its remaining namespace/resources.
Do not squash the two stages together or retarget step 2 before step 1 lands.

## Recovery and deferred work

To roll back step 1, revert its commit through GitOps. That recreates only the
empty Ollama namespace/policies and restores retired-tenant provisioning and
network access; it does not restore the previously deleted model volume or any
workloads. Restore the allowlist and tenant/network configuration before any
separately approved Plane/Sure application recovery. Preserve all encrypted
secrets and recovery archives. To roll back step 2, restore its empty Application
registration, then reverse step 1 only if the namespace is needed again.

Plane PVC/database disposal remains gated on recovery/retention acceptance.
Sure's final disposal remains gated on the MoneyMatter workflow cutover and
recovery checks. Shared PostgreSQL remains required by retained tenants.
Dashboard entries and DNS/tunnel/SSO objects are external integration cleanup;
seat MCP definitions belong to the private orchestration repository. Credential
revocation and SOPS edits remain user-operated. None is a side effect of these
GitOps changes.

[ArgoCD allow-empty pruning](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/)
explains the explicit empty-source setting. The separate unregister step avoids
relying on a deletion finalizer that the current Application does not have.
