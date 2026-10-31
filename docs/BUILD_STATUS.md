# CanDoHR build status

Following `docs/15-build-plan.md` (October 2026 spec).

| Step | Status | Notes |
|------|--------|--------|
| 0 Repository & tooling | **Ready for review on `cursor/step-0-repository-4cf6`** | pnpm monorepo, dev-pack at repo root, Worker stubs, platform guards, vinext at repo root for candohr.ca |
| 1 Database | **CI validates migrations** | All migration files under `supabase/migrations/`; GitHub Actions runs `supabase db reset` + schema smokes (no Docker needed on your PC). Link the CanDo Supabase project with `supabase link` + `supabase db push` when you want the cloud DB to match — do not expose CanDo schemas in the Data API. |
| 2+ | Not started | |

Spec mirror: `spec/dev-pack/` and `spec/claude/review/`.

**Configurable by design:** org settings and rules files drive behaviour; see `docs/22-values-and-fallbacks.md` and module decision docs 21–31.
