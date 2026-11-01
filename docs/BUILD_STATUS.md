# CanDoHR build status

Following `docs/15-build-plan.md` (October 2026 spec).

| Step | Status | Notes |
|------|--------|--------|
| 0 Repository & tooling | **On main** | pnpm monorepo, dev-pack at repo root, Worker stubs, platform guards, vinext at repo root for candohr.ca. The public site deploys when `main` changes. |
| 1 Database | **CI validates migrations** | All migration files under `supabase/migrations/`. GitHub Actions rebuilds a throwaway database and runs the schema smokes. The CanDo cloud database does not have these tables yet. Putting them there needs the database password, and that password is not used by this work. |
| 2 Shared foundations | **On main** | Money keeps exact cents (a JavaScript number is rejected). Dates use the employer's time zone. A change or a correction keeps one history row per day, and a later edit does not silently overwrite a future row. Each request sets the tenant, the user, and the roles on its database transaction. A test checks that two tenants sharing one connection cannot see each other's rows. |
| 3 Platform services | **On main** (pull request 2) | Sign-in checks the Supabase token, then loads the person from the directory (a token cannot name its own organization). The identity app creates, updates and disables users, and a client approves an outside payroll provider. A manager does not see home addresses or SINs. Audit rows hash the same way as the reference file. An hourly job seals those rows, signs the batch, and stores the signature where it cannot be overwritten. A former employee who left on 15 November 2026 keeps their own documents until 28 February 2028. |
| 4 Change sets, events, and live updates | **Ready for review on `cursor/step-4-change-sets-5a46`** | Every edit is a change set with an effective date. Checking it lists errors, warnings, and what else will change, and it writes nothing. Saving writes the history, the audit, and the event together, or it writes nothing. A past date asks whether this is a new fact or a correction. A future raise stays in place when a transfer changes a different field, and the new team is carried onto that raise. A different future rate asks you to keep, replace, or merge it. A transfer whose budget impact is over $10,000 goes to HR and then to finance. You cannot approve your own request, and someone who also reports to you on another job cannot approve you. Each day the latest audit seal can be copied to the customer. An event is delivered once, even if the sender restarts, and after ten failures it can be replayed. Open screens hear only the identifiers of units they are allowed to see. |
| 5+ | Not started | Core HR and later steps are not started. |

Spec mirror: `spec/dev-pack/` and `spec/claude/review/`.

**Configurable by design:** org settings and rules files drive behaviour; see `docs/22-values-and-fallbacks.md` and module decision docs 21–31.

## Waiting on the database

These items are left on purpose. They need the CanDo database password or a live database connection.

- The migration files are not pushed to the CanDo Supabase project.
- Hyperdrive is not created. The secret name for that password is `SUPABASE_DB_PASSWORD`.
- The hourly seal, the daily digest, and the event sender do not query Postgres yet. The tests use an in-memory store. When Hyperdrive is created, query caching must be off.
- Email sign-in and the return addresses are still switched on in the Supabase dashboard. See `docs/SETUP.md`.

## Files (R2)

R2 is turned on for the Cloudflare account. This step does not store files there, so no bucket was created and the site config does not attach one. Pay documents stay in Supabase Storage. Audit seals stay in the write-once anchor, not in R2.
