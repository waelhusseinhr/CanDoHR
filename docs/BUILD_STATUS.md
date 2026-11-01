# CanDoHR build status

Following `docs/15-build-plan.md` (October 2026 spec).

| Step | Status | Notes |
|------|--------|--------|
| 0 Repository & tooling | **Ready for review on `cursor/step-0-repository-4cf6`** | pnpm monorepo, dev-pack at repo root, Worker stubs, platform guards, vinext at repo root for candohr.ca |
| 1 Database | **CI validates migrations** | All migration files under `supabase/migrations/`; GitHub Actions runs `supabase db reset` + schema smokes (no Docker needed on your PC). Link the CanDo Supabase project with `supabase link` + `supabase db push` when you want the cloud DB to match — do not expose CanDo schemas in the Data API. |
| 2 Shared foundations | **Ready for review on `cursor/step-0-repository-4cf6`** | Money keeps exact cents (a JavaScript number is rejected). Dates use the employer's time zone. A change or a correction keeps one history row per day, and a later edit does not silently overwrite a future row. Each request sets the tenant, the user, and the roles on its database transaction. A test checks that two tenants sharing one connection cannot see each other's rows. |
| 3+ | Not started | |

Spec mirror: `spec/dev-pack/` and `spec/claude/review/`.

**Configurable by design:** org settings and rules files drive behaviour; see `docs/22-values-and-fallbacks.md` and module decision docs 21–31.
