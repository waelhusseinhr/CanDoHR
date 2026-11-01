# CanDoHR setup

This page is for Wa'el. It says what is connected, what the site uses, and which secret names still have to be filled in. It never contains a secret value.

The public site is https://candohr.ca. The database is the Supabase project named CanDo (`lasowjpgxlxijpaeezxe`, region US East). GitHub Actions deploys the site when `main` changes, after the tests pass. You do not deploy by hand.

## Sign-in

People sign in with email through Supabase Auth. The API checks the sign-in token against Supabase's published signing keys, then looks the person up in CanDo's own user list. A token cannot choose its own organization or its own role.

For a small customer, email sign-in is enough. Turn on email in the Supabase dashboard: Authentication, then Providers, then Email. These addresses may send people back to the site after they click a link in an email:

- `https://candohr.ca/**`
- `https://www.candohr.ca/**`
- `http://localhost:3000/**`
- `http://127.0.0.1:3000/**`

SAML (Microsoft Entra ID and Okta) is the sign-in for a customer who already has their own directory. It is set up in the Supabase dashboard under Authentication, then SSO, for the staging project, with the customer's own details. That test needs the customer's directory, so it is not switched on for candohr.ca yet. Google Workspace comes later.

On your own PC, `npm run dev` (or `pnpm dev` in this repo) serves http://localhost:3000. A phone on the same Wi-Fi uses the PC's Wi-Fi address and port 3000. Local sign-in uses the same Supabase project and the same email provider.

## GitHub Actions secret names

Values stay in GitHub. Settings, then Secrets and variables, then Actions. Do not put them in a file, a chat, or a commit.

| Name | What it is |
| --- | --- |
| `CLOUDFLARE_API_TOKEN` | Already used to publish the site. |
| `SUPABASE_URL` | `https://lasowjpgxlxijpaeezxe.supabase.co` |
| `SUPABASE_PUBLISHABLE_KEY` | The publishable (anon) key from Supabase, Project Settings, API. Safe for the browser. The tests do not need it; the site will. |
| `SUPABASE_DB_PASSWORD` | The database password for the CanDo project. Needed only to create the Hyperdrive connection. Not set from here. |
| `SUPABASE_SERVICE_ROLE_KEY` | The secret key that creates and disables sign-in accounts. Only the identity app may hold it, and only as a Cloudflare secret, not in GitHub Actions. The tests do not need it. Do not put it in the website. |

## Files (R2)

R2 is turned on for the Cloudflare account. No bucket was created, and `cloudflare.config.ts` does not attach one. Pay documents stay in Supabase Storage. Audit seals stay in the write-once anchor, not in R2. A bucket named `candohr` can be added later if a step actually needs it. Do not attach a binding before that bucket exists.

## Database connection (Hyperdrive)

Hyperdrive is the fast path from the site to Postgres. Creating it needs `SUPABASE_DB_PASSWORD`. That password is not in this checkout, so Hyperdrive was not created. When the password is stored under the secret name above, the connection is created with query caching turned off. The identity app does not get a database connection.

## What is already in the database

The schema files are in `supabase/migrations`. The CanDo project does not have those tables yet. This checkout has no database password, so the files were not pushed to the cloud database. GitHub tests rebuild a throwaway database on the runner. They do not use the CanDo password. Change sets, the event sender, and the daily seal copy are tested in memory for the same reason. They will use Hyperdrive, with query caching off, once `SUPABASE_DB_PASSWORD` is stored. Core HR (hire, jobs, positions, and the people screens) is tested the same way. The people list on the site is sample data until that connection exists.

Email sign-in and the return addresses above are also not switched on from here. The switch is in the Supabase dashboard: Authentication, then Providers, then Email, and Authentication, then URL Configuration. The addresses to allow are listed under Sign-in.
