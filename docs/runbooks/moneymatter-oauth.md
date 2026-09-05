# MoneyMatter MCP OAuth issuer correction

MoneyMatter v0.27.4 advertises the canonical site origin as its OAuth issuer in
`packages/backend/src/routes/oauth-metadata.route.ts`, while Better Auth uses
that origin plus `/api/v1/auth`. Codex rejects the callback after browser consent;
the token exchange does not complete.

The proposed frontend override serves corrected public discovery documents.
Both issuer and authorization_servers identify the existing Better Auth issuer,
and the RFC 8414 path-aware discovery URL is served. Resource, endpoint URLs,
scopes, PKCE support, and API/MCP proxy routes retain their deployed values.
No token is inserted and no issuer check is disabled.

The pinned image entrypoint renders nginx includes before executing container
args. The deployment then copies this override into the writable include and
starts nginx. The generated ConfigMap hash triggers a rollout when changed.
Review this workaround alongside image upgrades and remove it once upstream
discovery agrees with the auth provider.

Validation completed locally against the exact pinned frontend image, using its
normal non-root user and a mock backend without production credentials:

- nginx configuration syntax and frontend startup.
- Five discovery routes; issuer, resource, scopes, and JSON response types.
- Six proxy routes, including MCP, API, and legacy OAuth paths.
- POST forwarding for token and registration, plus homepage availability.
- Non-secret Kustomize render verifies the generated ConfigMap reference and
  namespace. The unchanged SOPS generator was omitted rather than decrypted.

Publication and deployment require approval. Merging would roll the frontend
through ArgoCD. After rollout, verify readiness and discovery, then request a
fresh MCP OAuth login; the failed authorization code cannot be reused.

Rollback: revert the change through GitOps. ArgoCD restores the original frontend
startup and prunes the unused generated ConfigMap. No database, secret, backend,
ingress, or image change needs reversal. The old strict-client login failure
returns with that rollback.

Sources:
- https://github.com/letehaha/budget-tracker/blob/v0.27.4/packages/backend/src/routes/oauth-metadata.route.ts
- https://github.com/letehaha/budget-tracker/blob/v0.27.4/packages/backend/src/config/auth.ts
- https://github.com/letehaha/budget-tracker/blob/v0.27.4/self-hosting/frontend/docker-entrypoint.sh
