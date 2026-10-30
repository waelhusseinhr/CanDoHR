# CanDoHR — notes for coding agents

Wa'el Hussein owns this product. GitHub account: `waelhusseinhr`. He is not highly technical. Write README text, on-screen copy, and explanations in plain language.

The public domain later is `candohr.ca`. Do not buy, attach, or configure that domain unless a task says so.

## Stack decisions

These are decided. Do not swap them for another stack.

| Piece | Decision |
| --- | --- |
| UI | Next.js App Router style, TypeScript, Tailwind CSS |
| Toolchain | [vinext](https://github.com/cloudflare/vinext) on Vite. Not the Next.js compiler. Not OpenNext. |
| Production host | Cloudflare **Workers**. Not Cloudflare Pages. Not a long-running Node server. |
| Package manager | **npm**. `package.json` sets `"packageManager": "npm"`. pnpm was not installed on this PC. Do not switch unless asked. |
| Worker name | `candohr` in `cloudflare.config.ts` |
| Local folder | `C:\Users\wael_\Documents\CanDoHR` |
| GitHub | Public repo `https://github.com/waelhusseinhr/CanDoHR`, branch `main` |

How this app was created (Cloudflare target, non-interactive):

```powershell
npx create-vinext-app@latest candohr --platform cloudflare --use-npm --yes --name candohr
```

The npm package name must stay lowercase `candohr`. The folder and GitHub repo stay `CanDoHR`.

If vinext tooling fails, stop and report the exact error. Do not fall back to Cloudflare Pages, OpenNext, or a different framework.

## What is already connected

- **Cloudflare account** `cd54a788a204d1515eb3b3224cd9594a`. `accountId` is set in `cloudflare.config.ts`. On this PC, sign in with `cf auth login`. Use the project's `cf` (`npx cf` or `node_modules/.bin/cf.cmd`).
- **Worker** `candohr` is deployed. Custom domains `candohr.ca` and `www.candohr.ca` returned HTTP 200 with the CanDoHR title.
- **DNS:** Hostinger mail records stayed (MX, SPF, DMARC, autoconfig, autodiscover). The old `www` CNAME to Hostinger's CDN was removed so the Worker could use `www`. Do not delete the MX or mail TXT records.
- **Supabase** organization `CanDo` (`wnmfevcahefzizowklxv`), project `CanDo` (`lasowjpgxlxijpaeezxe`), region `us-east-1`. It was paused and is active again. API URL: `https://lasowjpgxlxijpaeezxe.supabase.co`. The `public` schema has no tables. Do not create a second project unless asked.
- **Local env:** `.env.local` is gitignored and holds `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`. `.env.example` is committed with the URL and an empty key. Use the publishable key. Never commit the secret service-role key or the database password.

## Still not done

- **R2.** `cf r2 buckets list` returned 403, error 10042: enable R2 once in the Cloudflare dashboard. Then create a bucket named `candohr` and add `bindings.r2({ name: "candohr" })`. Do not add that binding before the bucket exists.
- **Hyperdrive.** Not created. `cf hyperdrive create` needs the Supabase database password, which is not in this repo. Keep the password out of git. After it exists, bind it with `bindings.hyperdrive({ id })`.
- **GitHub Actions.** No workflow yet. A deploy workflow needs a Cloudflare API token in GitHub Actions secrets.
- **Product schema and sign-in screens.** Not built. When you add tables in `public`, enable RLS and write policies for the real access rules. Do not use `user_metadata` for authorization.

## Where docs live

- `README.md` — plain-language guide for Wa'el (what the app is, how to start it, how to open it on a phone, what is not set up).
- `AGENTS.md` — this file. Stack, conventions, and local machine notes for agents.
- Longer product docs, when they exist, go in a `docs/` folder **in this repo**. Do not create that folder until there is a real document to put in it. Do not put secrets in docs.

## Layout

- `app/page.tsx` — home page (starter copy only).
- `app/layout.tsx` — root layout and page title.
- `app/api/hello/route.ts` — small JSON check: `{ "message": "CanDoHR is running" }`.
- `app/globals.css` — Tailwind.
- `vite.config.ts` — vinext plugin, Cloudflare Vite plugin, and the dev server host/port.
- `cloudflare.config.ts` — Worker config for `cf` and Cloudflare Vite plugin v2 (not a legacy `wrangler.toml`). Worker `candohr`, `nodejs_compat`, assets binding `ASSETS`, images binding `IMAGES`. Compatibility date is set by the generator.
- `next.config.ts` — Next.js-style config. vinext reads what it supports. Leave it unless a Next option is actually required.
- `tsconfig.json` — strict TypeScript. Path alias `@/*` maps to the repo root. `include` already lists `.cloudflare/types`.

`.cloudflare/` and `.vinext/` are generated and gitignored. Worker types appear during `dev` or `build`. For a type-check before that, run `npx cf workers types`.

## Run locally

```powershell
cd C:\Users\wael_\Documents\CanDoHR
npm install
npm run dev
```

`vite.config.ts` sets the dev server to `host: "0.0.0.0"`, `port: 3000`, `strictPort: true`. It listens on every network interface so a phone on the same Wi-Fi can connect. It will fail if port 3000 is already taken, instead of quietly moving to another port.

- This PC: `http://localhost:3000`
- Another device: `http://<LAN IPv4>:3000`

Find the LAN IPv4 with `ipconfig`. Use the Wi-Fi adapter’s IPv4 that looks like `192.168.x.x`. Ignore `127.0.0.1` and `169.254.x.x` (those are link-local, not the Wi-Fi address).

Windows Firewall may prompt the first time Node.js listens on all interfaces. Allow **private** networks so phones on home Wi-Fi can connect. Do not add a broad public firewall rule.

Scripts:

- `npm run dev` — dev server
- `npm run build` — production Worker build
- `npm run start` — preview the built Worker locally (`vite preview`)
- `npm run deploy` — `vinext-cloudflare deploy`. Do not run until deploy is requested.

## This PC

- Node for this app: `C:\Program Files\nodejs`, now **v22.23.4**. The PC originally had v22.14.0. `npm run dev` then failed with: `cloudflare.config.ts loading requires Node.js v22.18.0 or higher.` The `cf` package also asks for `^22.23.0 || ^24.22.0 || ^26.12.0`. It was upgraded with `winget upgrade --id OpenJS.NodeJS.22` (the Windows installer may show an administrator prompt). Stay on Node 22.23 or newer. Do not switch stacks if a future Node error appears — upgrade Node and report the exact error.
- Git and `gh` are installed but were not on `PATH`. In a fresh PowerShell:

```powershell
$env:Path = "C:\Program Files\GitHub CLI;C:\Program Files\Git\cmd;C:\Program Files\nodejs;" + $env:Path
```
- Git: `C:\Program Files\Git\cmd\git.exe`. It was not on `PATH` until added as above. No global `user.name` / `user.email` was set. Do not change git config. If a commit needs an identity, pass `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME`, and `GIT_COMMITTER_EMAIL` for that command only.
- GitHub CLI: `C:\Program Files\GitHub CLI\gh.exe` (also not on `PATH` by default). `gh auth status` was **not logged in** when this repo was created. Do not invent a token. If `gh` is still logged out, Wa'el must run `gh auth login` himself (GitHub.com, HTTPS, login with the browser) before anyone can push.

## Conventions

- Plain language in anything Wa'el will read.
- Do not commit secrets. `.gitignore` ignores `.env*`, `node_modules`, `.next`, `.vinext`, and `.cloudflare`. No Supabase keys, Cloudflare tokens, or `.env` files in git.
- Do not deploy and do not create cloud resources unless the task says so.
- Keep edits scoped to the task. This repo started as the vinext scaffold plus the README, this file, a CanDoHR title on the home page, and the dev server bound to all interfaces on port 3000.
