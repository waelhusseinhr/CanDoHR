# CanDoHR build status

Following `docs/15-build-plan.md` (October 2026 spec).

| Step | Status | Notes |
|------|--------|--------|
| 0 Repository & tooling | **In progress on branch `cursor/step-0-repository-4cf6`** | pnpm monorepo, dev-pack copied to repo root, Worker stubs, CI, platform guards, vinext still at repo root for candohr.ca |
| 1 Database | **Started** | Supabase migration files copied from `schema/`; apply locally with `supabase start` then `supabase db reset` when Docker is available |
| 2+ | Not started | |

Spec mirror: `spec/dev-pack/` and `spec/claude/review/`.

**Configurable by design:** org settings and rules files drive behaviour; see `docs/22-values-and-fallbacks.md` and module decision docs 21–31.
