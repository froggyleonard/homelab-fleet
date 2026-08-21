# 0007 — Matrix (Synapse) as the notification backbone

- Status: **accepted** (2026-08-20)
- Deciders: operator (solo)

## Context and problem statement

I need a push notification backbone for the fleet: first consumer is the n8n
daily financial driver (in-depth digests — balances, transactions), later
Alertmanager (when the GLP stack lands) and Proxmox webhook targets. The
finance content is the constraint: it must not transit a third-party chat
cloud. I'm on an iPhone today (Android planned later), and I want a
Discord-like experience — channels, per-channel mute, desktop + mobile.

## Considered options

1. **ntfy** (the original plan) — self-hosted, excellent on Android, but iOS
   delivery is the known-weak path (the native app needs the public ntfy.sh
   relay for wake-ups and delivery is unreliable). Content-private, but
   unreliable on my primary device defeats a daily driver.
2. **Discord webhooks/bot** — path of least resistance, reliable push
   everywhere, zero hosting. Rejected: Discord is TLS-only, not E2EE — the
   provider can read every message, and these messages are my finances.
3. **Matrix (Synapse) self-hosted** — Element clients give the Discord-like
   UX; iOS push works reliably via Element's gateway while carrying only
   event IDs (content is fetched from my server); rooms map to channels
   with per-room notification settings; n8n has a native Matrix node.
4. **Pushover-class SaaS** — reliable iOS push, but third-party cloud again.

## Decision

Option 3: a **closed** Synapse homeserver on cluster-apps.

- **server_name `froggyleonard.com`** (I am `@freddy:froggyleonard.com`) —
  permanent identity; the server itself runs at
  `matrix.apps.froggyleonard.com` behind the Cloudflare Tunnel, delegated
  via `/.well-known/matrix/client` on the apex (Cloudflare-side static
  JSON). No server well-known while federation is closed.
- **Federation closed**: client-only listener, no 8448 anywhere, explicit
  `federation_domain_whitelist: []` (empty = matches no servers).
  Registration disabled; accounts are me + the n8n bot.
- **Dedicated PostgreSQL** in-namespace (postgres:18.6, C-locale initdb) —
  first app under the native-DB-per-app doctrine, with its own nightly
  integrity-checked pg_dump CronJob (newest 7).
- **E2EE off** for now (bot/bridge friendliness on a closed server); push
  payloads exclude message bodies (`push.include_content: false`), so
  Apple/Element see routing metadata only.
- n8n posts via its native Matrix node (bot account token); matrix-hookshot
  for Alertmanager/Proxmox webhooks is a deliberate later phase.

## Consequences

- **Media policy (accepted):** uploaded attachments are retained **90 days
  since last access** (never-accessed: 90 days from creation) and are **not
  backed up** — a restore recovers accounts, rooms, and full message text,
  but not attachments; an old message can outlive its image. Fine for
  notification screenshots; revisit before Matrix ever carries durable
  documents.
- **Self-monitoring trap (accepted):** the backbone rides cluster-apps, so
  alerts about cluster-apps being down may not deliver. Revisit an
  out-of-band dead-man's-switch when the GLP monitoring stack lands.
- The namespace and standalone PVCs carry `Prune=false` — removing the app
  from git leaves them OutOfSync by design; teardown is a deliberate,
  gated act with an off-namespace backup copy first.
- Opening federation later is config + well-known additions; my user ID
  never changes.

## Addendum — auth is MAS + Authentik (2026-08-21)

The original password-only design failed on first contact with the primary
client: **Element X (26.08.2) refuses homeservers without OIDC-native auth**
(it demands MAS; classic password login is desktop/web-only). Fix:
**Matrix Authentication Service 1.23.0** now fronts all authentication, with
**Authentik as its upstream OIDC provider** — one more moving part, but auth
lands on the fleet's existing identity plane instead of a parallel password
store.

- MAS runs in the matrix namespace (own DB on the same dedicated PG
  instance), public at **account.froggyleonard.com** via the same
  tunnel-translation pattern as the homeserver (`auth.*` was unavailable —
  Authentik already answers it). Synapse delegates via the stabilized
  `matrix_authentication_service` block; the legacy
  `/login|/refresh|/logout` client endpoints route to MAS's compatibility
  layer.
- Public entry is **matrix.froggyleonard.com** (Cloudflare tunnel translates
  to the internal `matrix.apps.` host); the `.apps` names never had public
  DNS, so the ADR's original hostname wording describes the internal host
  only.
- Existing accounts (me + the bot) were migrated with `syn2mas` —
  same user IDs, imported password hashes retained as a fallback scheme.
  My login is Authentik SSO end-to-end.
- The **n8n bot authenticates with a MAS compatibility token** (device
  `N8N`). MAS offers no expiry knob for these; posture is revoke + re-issue
  on suspicion.
- `registration_shared_secret` is removed from Synapse (this change) —
  account administration now lives in MAS; the shared-secret registration
  API is retired.
- n8n's egress NetworkPolicy gained a matrix-namespace :8008 allow — the
  bot posts in-cluster, not through the tunnel.
