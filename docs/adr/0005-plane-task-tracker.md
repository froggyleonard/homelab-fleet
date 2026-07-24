# 0005 — Plane CE as the fleet task tracker

- Status: **accepted** (2026-07-24)
- Deciders: operator (solo)

## Context and problem statement

I want Agile task tracking (backlog, sprints, epics, estimates) across all my
repos and projects, and I want my AI agents to create and manage tasks directly —
which makes first-class MCP support a hard requirement. Self-hosted strongly
preferred. Push-based notifications matter more to me than dashboards.

## Considered options

1. **Plane CE** — official, actively maintained MCP server (100+ tools incl.
   cycles/modules/estimates, works against self-hosted CE), official Helm chart,
   AGPL, webhooks included. Cost: ~10–12 pods, the heaviest of the viable picks.
2. **Forgejo/Gitea issues + official gitea-mcp** — composes with the planned
   self-hosted forge, tiny footprint, but kanban project boards have **no REST
   API at all** (Forgejo #5330 stalled), so agents can only touch issues/labels/
   milestones. No sprint semantics.
3. **Vikunja** — best ops story (single binary, official Helm, signed per-project
   webhooks) but structurally no sprints/epics/estimates, community-only MCP.
4. **OpenProject** — official MCP is Enterprise-paywalled *and* read-only.
5. **Huly** — heaviest stack (CockroachDB+Elasticsearch+Redpanda, 8–16 GB); the
   hosted service was defunded and shut down July 2026.
6. **Taiga** — best classic Scrum model, but effectively in maintenance mode.
7. **Leantime** — markets itself as ADHD-friendly (relevant to me), but the MCP
   server is a paid beta plugin and there are no generic outbound webhooks.
8. **GitHub Projects v2 + official MCP** — the strongest MCP implementation of
   the lot (Projects v2 iterations, custom fields), but SaaS.

## Decision

Option 1, Plane CE — the only candidate where self-hostable, official
write-capable MCP, and real sprint semantics intersect. Deployed on cluster-apps
via this repo: pinned `plane-ce` Helm chart, external PostgreSQL as a shared-PG
tenant (SSD-backed, covered by the nightly dump CronJob), chart-managed
valkey/rabbitmq/minio on Longhorn, all credentials in one SOPS secret consumed
through the chart's `external_secrets` slots. The chart's native Traefik
IngressRoute carries the multi-service path routing.

## Consequences

- ~10–12 pods on cluster-apps; `max_connections` on shared PG raised to 150.
- Agents reach Plane through the official `plane-mcp-server` (stdio) from the
  workstation; the API key never enters a repo.
- Notifications: Plane webhooks → n8n → push (ntfy once deployed). Pull
  dashboards are not the interface; the cadence lives in n8n.
- Public exposure stays off until fronted by Authentik; until the cert-manager
  issuer is unblocked, access is Tailscale-only with the default cert.
- If the footprint ever hurts, Vikunja is the documented lightweight fallback;
  Forgejo issues may complement for repo-native bugs once the forge lands.
