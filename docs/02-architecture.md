# 02 · Architecture

Platform decision (October 2026): **Supabase** for PostgreSQL, authentication and file storage, in its Canada (Central) region; **Cloudflare** Workers for the API, background jobs and live updates; **GitHub** for code, reviews and deployments; **Cursor** and other AI coding agents for the build, all working from `AGENTS.md`. A small AWS footprint remains for two jobs neither platform does in Canada: encryption keys and write-once audit anchoring.

## Shape

A modular monolith on Cloudflare Workers: one codebase with strict module boundaries, deployed as a few Workers that share packages. One PostgreSQL database on Supabase with a schema per module, and an event outbox. Modules talk through published service interfaces and events, never by reading another module's tables directly.

```
              ┌──────────────── Web app (React, Workers static assets) ────────────────┐
              │ Employee · Manager · HR · Payroll · Admin portals                      │
              └───────────────┬───────────────────────────────┬────────────────────────┘
                  REST/JSON   │                               │  WebSocket (live updates)
┌─────────────────────────────▼─────────────────┐   ┌─────────▼──────────────────────────┐
│ apps/api — Hono on Workers                     │   │ apps/realtime — Durable Objects     │
│ JWT check · tenant context · Zod · rate limits │   │ OutboxRelay (alarm loop)            │
│ change-set service (the only write path)       │   │ SessionHub (hibernating WebSockets) │
│ 14 modules · rules engine · platform services  │   └─────────┬──────────────────────────┘
└───────┬───────────────────────┬────────────────┘             │ reads outbox
        │ Hyperdrive            │ Queues                       │
        │ (caching off)         ▼                              │
        │            ┌──────────────────────────────┐          │
        │            │ apps/jobs — Queue consumers,  │          │
        │            │ Cron Triggers, Workflows      │          │
        │            │ payroll buckets · retro ·     │          │
        │            │ files · sealing · replay      │          │
        │            └──────────┬───────────────────┘          │
        ▼                       ▼                              ▼
┌──────────────────────────────────────────────────────────────────────────────────────┐
│ Supabase, ca-central-1: PostgreSQL 16 (RLS per tenant, outbox) · Auth (SAML SSO, MFA) │
│ · Storage (documents, generated files) · read replica for analytics                   │
└──────────────────────────────────────────────────────────────────────────────────────┘
        │ envelope keys, audit signing                │ audit anchors
┌───────▼────────────────────────┐        ┌───────────▼─────────────────────────────────┐
│ AWS keys account, ca-central-1 │        │ AWS anchor account, ca-west-1: S3 Object     │
│ KMS (per-tenant keys, signing) │        │ Lock, compliance mode (hashes only)          │
└────────────────────────────────┘        └──────────────────────────────────────────────┘
```

## Technology choices

| Concern | Choice | Notes |
| --- | --- | --- |
| Language | TypeScript 5, strict mode | Shared types between backend and frontend in `packages/shared` |
| Runtime | Cloudflare Workers with the `nodejs_compat` flag | Limits that shape the design: 128 MB memory per isolate; CPU up to 5 minutes per request; 15 minutes wall time for Queue consumers and hourly or slower Cron Triggers |
| HTTP | Hono with `@hono/zod-openapi` | OpenAPI generated from route schemas and checked against `api/openapi.yaml` |
| Validation | Zod | Every input validated at the edge; the same schemas generate the TypeScript types |
| Database | Supabase PostgreSQL 16 in `ca-central-1` with `btree_gist`, `pgcrypto`, `citext` | Range types and exclusion constraints enforce effective dating. Pro plan or above with point-in-time recovery. Compute size set by load test (Step 20) |
| Connection | Cloudflare Hyperdrive to Supabase's **direct** connection string, **query caching disabled**, one Hyperdrive configuration per database role | Hyperdrive pools in transaction mode, so tenant context is set with `SET LOCAL` inside each transaction. Caching is off because it would serve stale `asOf`/`knownAt` reads and keep personal data in Cloudflare's cache |
| Query layer | Kysely over `pg` (node-postgres) | Raw SQL migrations, no ORM magic |
| Migrations | Supabase CLI, `supabase/migrations/` | Timestamped files; applied by GitHub Actions, never from a laptop to production |
| Jobs | Cloudflare Queues (one message per payroll bucket, retro batch, file job or notification batch), Workflows for multi-step runs (pay run lifecycle, year-end, bulk imports), Cron Triggers for schedules | Bucket claims still use `FOR UPDATE SKIP LOCKED` so a redelivered message never double-writes (`06` §9) |
| Events | Transactional outbox table; the `OutboxRelay` Durable Object polls it on a short alarm loop and dispatches to Queues (subscribers), `SessionHub` (live updates) and the webhook queue | Exactly-once effect through idempotency keys (`05` §4) |
| Live updates | `SessionHub` Durable Objects holding hibernating WebSockets, one per tenant shard | Messages carry identifiers only, never personal data |
| Money | `decimal.js` with 28 significant digits; `NUMERIC(14,2)` columns | Never use JS `number` for money |
| Frontend | React 18, Vite, TanStack Query, React Router, React Hook Form + Zod; deployed as Workers static assets on a custom domain | |
| Components | Radix UI primitives with an in-house design system; the Lovable demo is the visual reference | WCAG 2.1 AA |
| Org chart | `@xyflow/react` (React Flow) with `elkjs` in a Web Worker | Drag and drop, keyboard alternatives, virtualized for 50,000 nodes |
| i18n | i18next with `en-CA` and `fr-CA` resource files | No hard-coded UI text |
| Auth | Supabase Auth: SAML 2.0 SSO per customer identity provider (Pro plan and above), email sign-in with MFA for small customers. Workers verify Supabase JWTs against the project's published signing keys | Tenant and roles are read from `platform.app_user` and `platform.role_grant`, never from user-editable token metadata |
| Provisioning | CanDo is the source of truth for people: a hire creates the CanDo user, a termination disables it at the time Module 11 sets. Customers who provision from their IdP use CanDo's own SCIM 2.0 endpoint in `apps/identity`; outbound provisioning to the customer's IdP is an adapter (`11` §3) | Supabase Auth does not provide SCIM itself |
| Files | Supabase Storage in the same project, private buckets per tenant prefix, accessed through its S3-compatible keys (storage only); downloads by short-lived presigned URLs issued by the API after a permission check | R2 has no Canadian jurisdiction, so R2 holds only non-personal assets (build artifacts, public images) |
| Field-level encryption | Envelope encryption with per-tenant data keys from AWS KMS (`ca-central-1`, keys account); data keys cached in memory for minutes only; Workers call KMS with SigV4 (`aws4fetch`) | Supabase Vault was considered and rejected: the keys would sit in the same database as the data |
| Search | PostgreSQL full-text search with `unaccent` (French) | |
| Analytics store | Supabase read replica in `ca-central-1` for reports, exports and BI connectors | Heavy queries never touch the primary (`requirements/12`) |
| Observability | Workers Logs and Logpush through a redacting Tail Worker; Supabase logs; OpenTelemetry traces | No personal data in any log, trace or metric |
| Audit anchoring | AWS KMS asymmetric signing key (sign-only for the sealing job) and an S3 bucket with Object Lock in compliance mode in a **separate AWS account** in `ca-west-1` | `10` §5. R2 bucket locks were considered and rejected: no Canadian jurisdiction, and Cloudflare's documentation describes removing lock rules through the dashboard, Wrangler or the API |
| Infrastructure as code | `wrangler.jsonc` per Worker; `supabase/config.toml`; Terraform for Cloudflare account resources (DNS, Hyperdrive, Queues, R2), the two AWS accounts and Supabase project settings | |
| CI/CD | GitHub Actions: type-check, lint, unit, Workers integration tests, database tests against the local Supabase stack, payroll and agreement fixtures, audit vectors, accessibility, OpenAPI diff; deploys through GitHub Environments | `15` §Working with AI agents and GitHub |

## Repository layout

```
cando/
  apps/
    api/                 Hono on Workers: REST API, auth check, tenant context, change sets, modules
    jobs/                Queue consumers (payroll buckets, retro, files, notifications), Cron Triggers
                         (audit sealing, nightly replay, accrual runs, reminders), Workflows
    realtime/            Durable Objects: OutboxRelay, SessionHub
    identity/            SCIM 2.0 endpoint and Supabase Auth admin calls; no database binding
    web/                 React app (portals), deployed as static assets
    assistant/           smart assistant service (Step 19)
  packages/
    shared/              Zod schemas, types, money and date utilities
    platform/            identity, workflow, audit, documents, notifications, i18n
    changesets/          the single write path: operations, validation, cascade, commit
    rules/               rule editions loader, agreement rules, evaluation
    payroll-engine/      pure calculation library (no I/O) — mirrors reference/payroll_reference.py
    db/                  Kysely setup, Hyperdrive connection helper, tenant transaction wrapper
    keys/                KMS envelope encryption client
    modules/
      core-hr/ recruitment/ payroll/ compensation/ benefits/ time-leave/ performance/
      learning/ succession/ engagement/ offboarding/ analytics/ compliance/
  supabase/
    config.toml
    migrations/          20261018000001_initial.sql (schema/cando_schema.sql), 20261018000002_roles.sql,
                         20261020000003_enterprise_structures.sql, then new files only
    seed.sql             reference data (provinces, holidays, rule editions)
    seeds/demo/          the three fictional demo tenants (`14` §4); never loaded into production
  infra/                 Terraform: Cloudflare, AWS keys and anchor accounts, Supabase settings
  rules/                 copied from this pack: statutory, employer-taxes, employment-standards, agreements
  tests/                 copied from this pack; must all pass
  .github/               workflows, CODEOWNERS, pull request template
  .cursor/rules/         Cursor project rules (point to AGENTS.md)
  AGENTS.md  CLAUDE.md
```

## Multi-tenancy

- Every tenant-owned table has `tenant_id uuid NOT NULL` and row-level security: `USING (tenant_id = current_setting('app.tenant_id')::uuid)`.
- Each API request opens a transaction through Hyperdrive as the `cando_app` role and runs `SET LOCAL app.tenant_id` and `SET LOCAL app.user_id` first. The tenant comes from `platform.app_user` for the verified user, never from the request body or token metadata.
- `cando_app` has no `BYPASSRLS` and does not own the tables. Migrations run as Supabase's `postgres` role from GitHub Actions. The audit sealing job uses its own role, `cando_sealer`, through its own Hyperdrive configuration.
- **Supabase's Data API (PostgREST), GraphQL and Realtime database changes are not used for business data.** None of CanDo's schemas is exposed, and the roles migration revokes every privilege on them from `anon` and `authenticated`. The only way to read or change business data is the CanDo API, so the change-set rule holds.
- **The Supabase `service_role` key bypasses row-level security.** It lives only in the `apps/identity` Worker, which has no database binding and calls only the Auth admin endpoints. It is never given to `apps/api`, `apps/jobs`, an AI agent or a developer laptop.
- Large tenants (public sector, OCAP® nations) can be placed on their own Supabase project. The code path is the same; only the Hyperdrive configuration changes.
- Reference data shared by all tenants (provinces, rule editions, holiday rules) lives in the `ref` schema without RLS and is read-only to the application role.

## Data residency

| Data | Where it lives or flows | Control |
| --- | --- | --- |
| Database, backups, point-in-time recovery | Supabase `ca-central-1` | Project region; confirm with Supabase that backups stay in the region |
| Documents and generated files (pay statements, T4s, bank files) | Supabase Storage in the same project | Never R2 |
| Encryption keys | AWS KMS `ca-central-1` | Separate keys account |
| Audit anchors (hashes and signatures only) | AWS S3 `ca-west-1` | Separate anchor account, Object Lock |
| Processing in Workers | The Cloudflare data centre that receives the request; with placement set to Supabase's region, database work runs near it | Placement hint `aws:ca-central-1` in every Worker that touches the database (confirm at Step 0; `16` verify items). For customers that require processing in Canada only, Cloudflare Regional Services lists Canada as a region (Data Localization Suite); confirm plan and compatibility for Hyperdrive and Queues with Cloudflare |
| Hyperdrive | Pool placed near the database | Query caching disabled |
| Durable Objects and Queues | Messages and cursors only, never personal data | Rule in `AGENTS.md` |
| Logs | Redacted before they leave the Worker | Log-redaction test in CI |

**Disaster recovery.** Supabase offers one Canadian region, so the recovery region in earlier drafts (`ca-west-1`) is now covered by an encrypted nightly logical backup written to a separate AWS backup account in `ca-west-1`, with a tested restore runbook. Inside the region, point-in-time recovery gives an RPO of minutes; for the loss of the whole region the RPO is the last nightly backup unless a stronger arrangement is agreed with Supabase (`16`, Q15).

## Transactions and consistency

- A change set commits in one database transaction: the business rows, the audit entry, and the outbox events.
- Projections that need instant consistency (org chart, employee profile, position counts) are computed by query from the effective-dated tables. Heavier projections (analytics, search) update from events within seconds.
- Optimistic concurrency: every editable aggregate carries a `version` number. A change set built on an old version is rejected with `409 CONFLICT` and the current state.
- Payroll results are immutable once finalized. Corrections are new results that reference the originals.
- A locked pay run reads business data as of `inputs_known_at` and rules by pinned content hash, and is calculated in buckets of disjoint pay subjects (`06` §8–9). Each bucket is one Queue message; its consumer claims the bucket row with `FOR UPDATE SKIP LOCKED`, writes the bucket's results in one transaction, and acknowledges the message only after commit. A redelivered message finds the bucket already done and stops.
- Every audit row is hashed on insert; an hourly Cron Trigger seals rows into signed Merkle batches anchored outside the database (`10` §5).

## Live updates

- The web app opens one WebSocket per session to a `SessionHub` Durable Object. After a change set commits, the `OutboxRelay` pushes a small message, for example `{ "type": "org.changed", "asOf": "2026-11-01", "units": ["…"] }`, to sessions that subscribed to the affected entities and are allowed to see them.
- The client invalidates the matching TanStack Query caches and refetches through the API. Nothing is pushed that the user could not read through the API.

## Performance targets

| Target | Value |
| --- | --- |
| Records | 100,000 active employees per tenant |
| Pay run | 50,000 employees calculated in under 15 minutes (100 buckets consumed in parallel); 2-hour window end to end with approvals and files |
| Org chart | First paint under 2 s for 5,000 visible nodes; 50,000-node tenants load by subtree |
| API | p95 under 300 ms for reads, under 800 ms for single change sets, measured from a Canadian client |
| Availability | 99.9% monthly; RPO 15 minutes within the region; RTO 4 hours |

Large files (T4 XML for 50,000 slips, bank files, exports) are written in streamed chunks to Supabase Storage so no Worker holds the whole file in its 128 MB of memory.

## Environments

| Environment | Supabase | Cloudflare | Who deploys |
| --- | --- | --- | --- |
| Local | `supabase start` (Docker) | `wrangler dev` (local Workers, Queues, Durable Objects) | Developer or agent |
| Preview | Supabase branch per pull request, or a shared dev project | Preview Workers per pull request | GitHub Actions |
| Staging | Staging project in `ca-central-1` | Staging Workers environment | GitHub Actions after merge to `main` |
| Production | Production project in `ca-central-1`; dedicated projects for large tenants | Production Workers environment | GitHub Actions, only after a human approves the GitHub Environment |

Non-production environments never hold real personal data. Configuration (rules, agreements, workflows) moves between environments as signed, versioned bundles with approval.

## What must never happen

- A second write path that bypasses change sets, including Supabase's Data API, GraphQL or direct client writes
- The `service_role` key in any Worker that can reach the database, in an AI agent's context, or on a laptop
- Hyperdrive query caching turned on
- Personal data in R2, Workers KV, Durable Object storage, Queue messages, logs, analytics events or AI prompts beyond what the permission check allows
- Money in floating point
- A statutory value or agreement term hard-coded in source code
- A finalized pay result edited in place
- An active rule edition or agreement version edited in place, or a locked run reading rules that are not its pins
- Two open pay runs holding the same person in the same payroll account
- An audit row updated or deleted
- Data leaving Canada for a tenant whose residency setting is Canada
- A migration applied to staging or production from anywhere but GitHub Actions

## Sources (checked October 2026)

- Supabase regions (Canada: `ca-central-1` only): https://supabase.com/docs/guides/platform/regions
- Supabase Auth SAML single sign-on: https://supabase.com/docs/guides/auth/enterprise-sso/auth-sso-saml
- Cloudflare Hyperdrive with Supabase (use the direct connection string): https://developers.cloudflare.com/hyperdrive/examples/connect-to-postgres/supabase
- Cloudflare Hyperdrive query caching: https://developers.cloudflare.com/hyperdrive/concepts/query-caching/
- Cloudflare R2 data location (jurisdictions `eu`, `fedramp`, `us`; no Canada): https://developers.cloudflare.com/r2/reference/data-location/
- Cloudflare R2 bucket locks: https://developers.cloudflare.com/r2/buckets/bucket-locks/
- Cloudflare Workers placement (`placement.region` as `{provider}:{region}`): https://developers.cloudflare.com/workers/configuration/placement/
- Cloudflare Workers limits: https://developers.cloudflare.com/workers/platform/limits/
- Cloudflare Data Localization Suite, region support: https://developers.cloudflare.com/data-localization/region-support/
- Cursor project rules: https://cursor.com/docs/context/rules
