# 10 · Security, privacy and audit

Platform services named here are those in `02` (Supabase, Cloudflare Workers, AWS KMS and S3 for keys and anchors).

## 1. Identity and access

- Sign-in through Supabase Auth: SAML 2.0 single sign-on with each customer's identity provider (Microsoft Entra ID, Okta, Google and others), or email sign-in for small customers. MFA is required for HR, payroll, finance and admin roles. Passkeys are offered when Supabase Auth supports them for sign-in (`16`, Q19).
- Every Worker verifies the Supabase JWT against the project's published signing keys, then loads the user's tenant, roles and scopes from `platform.app_user` and `platform.role_grant`. Nothing in the token that a user can edit (user metadata) is trusted.
- Provisioning: CanDo is the source of truth for people. A hire creates the CanDo user and a termination disables it at the time Module 11 sets. Customers who provision from their identity provider use CanDo's SCIM 2.0 endpoint in `apps/identity`, which creates, updates and disables Supabase Auth users through the admin API and records each call in the audit log.
- The Supabase `service_role` key is held only by `apps/identity`, which has no database binding.
- Sessions: 8-hour absolute, 30-minute idle for privileged roles, re-authentication for sensitive actions (bank file release, SIN reveal, role changes). Supabase SAML has no single logout, so session limits are what end access.

## 2. Authorization model

A permission check answers: can this **user**, acting in this **role**, perform this **action** on this **field class** of this **record**, given the record's **scope**?

| Dimension | Values |
| --- | --- |
| Role | Employee, Manager, HRBP, HR admin, Payroll processor, Payroll approver, Finance, Recruiter, Hiring manager, LR specialist, Auditor, Tenant admin, Funder report viewer, Assistant (service identity, always acting on behalf of a user) |
| Action | read, propose (create change set), approve, export, reveal (sensitive), configure |
| Field class | public directory, employment, personal, compensation, payroll restricted (SIN, banking, garnishments), health and accommodation, self-identification, investigation |
| Scope | self, direct reports, reporting subtree, org units in any hierarchy, legal entities, payroll accounts, bargaining units, agreements, funding sources, locations, all (`17` §3.6) |

Policies are data (`platform.role_grant` with scope expressions) and are evaluated in one library used by the API, the live-update relay, exports and the assistant. Every list endpoint filters in SQL by scope, not after fetching.

Segregation of duties is enforced: nobody approves their own change set; nobody changes bank details and releases payment; nobody processes and approves the same pay run; nobody edits their own pay.

## 3. Data protection

- TLS 1.2+ in transit. At rest: Supabase encrypts the database, backups and storage; field-level encryption adds per-tenant envelope keys from AWS KMS for SIN, bank account numbers, garnishment details, health and accommodation notes, and self-identification. Values are stored as `bytea` plus a key ID and decrypted only in the Worker that needs them; plaintext data keys stay in memory for minutes and are never written anywhere.
- SIN shown masked (`*** *** 123`); reveal requires the `reveal` permission and a reason, and is logged.
- No personal data in logs, traces, metrics, analytics events, Queue messages, Durable Object storage, Workers KV or R2. A logging wrapper redacts known fields, a Tail Worker redacts again before Logpush, and a test rejects objects with sensitive keys.
- Hyperdrive query caching is disabled, so no query result is cached outside the database.
- Backups are encrypted and in Canada: Supabase backups in `ca-central-1`, plus a nightly encrypted logical backup in a separate AWS backup account in `ca-west-1`. Restores are tested quarterly.

## 4. Privacy

| Requirement | Implementation |
| --- | --- |
| PIPEDA and provincial private-sector acts (AB, BC PIPA; Quebec Law 25) | Purpose recorded at collection; consent records for voluntary data; access and correction requests as tracked cases; breach register and notification workflow |
| Quebec Law 25 | Privacy impact assessment record before enabling features that move Quebec employees' data outside Quebec; confidentiality incident register; privacy officer contact in the portal |
| Public-sector statutes (FOI and privacy acts) | Retention schedules per class; export packages for access-to-information requests with redaction support |
| OCAP® for First Nations customers | Tenant option: a dedicated Supabase project, its own KMS keys and anchor bucket, the nation controlling access grants and the export of all data on request |
| Self-identification data | Separate table and key; reports only in aggregate with minimum group sizes (suppress groups under 10) |
| Retention | Schedule per data class and jurisdiction (payroll records at least 6 years after year end for CRA); legal holds; destruction logged |
| Electronic monitoring (Ontario) | Policy document distribution and acknowledgement through Module 01 documents |
| Sub-processors | Supabase, Cloudflare and AWS listed in the customer's data processing agreement with the region each uses |
| AI | See `12-smart-assistant.md`. No customer data used to train models. AI coding agents never receive production data or production keys (`15` §Working with AI agents and GitHub). |

## 5. Audit and tamper evidence

### What is logged

Every change set (its operations, before and after values, reason and approvals), every reveal of sensitive data, every export, every login and permission change, every SCIM call, every pay run state change, every rule activation. A change set commit writes an audit entry whose `after` holds the SHA-256 of the canonical change set. A pay result finalization writes one with the SHA-256 of the result and its lines. So the audit log covers change sets and pay results as well.

The auditor role is read-only and time-limited, and can use `knownAt` queries to see what the system showed at any moment.

### Threat model

| Threat | Defence |
| --- | --- |
| The application edits or deletes audit rows | The application role has INSERT and SELECT only on `platform.audit_entry` |
| A database administrator, a Supabase operator, or a restored backup rewrites rows and recomputes every hash | Hourly Merkle roots stored outside Supabase in storage that nobody can delete or overwrite, signed with a key the database cannot reach, and copied to the customer |
| A single damaged row makes the whole history unverifiable | Batches are verified independently. The verifier names the batch and the rows that fail; every other batch still verifies. |
| Inserts slow down at scale | No per-row chain. Rows are written in parallel and only the sealing job, once an hour, reads them in order. |

### How it works

1. **Leaf hash on insert.** Each audit row stores `leaf_hash = SHA-256(0x00 ‖ canonical(row))` over a fixed field list (IP address and user agent are excluded so they can be redacted later without breaking proofs). Inserts never wait for each other.
2. **Hourly sealing job, per tenant.** A Cloudflare Cron Trigger in `apps/jobs` runs hourly (15-minute limit) as the `cando_sealer` role. It takes rows with no batch, in `audit_id` order, and assigns them to batch *n*. It computes the RFC 6962 Merkle root over their leaf hashes, then `batch_hash = SHA-256(0x02 ‖ previous batch_hash ‖ root ‖ canonical(header))`. The header holds tenant, batch number, first and last audit ID, leaf count and the sealing time. Rows still in uncommitted transactions are not visible yet, so they simply fall into the next batch. Once a day, a batch is sealed even if it is empty, so quiet periods are provable too. Tenants are processed in parallel through a Queue when one hour's work does not fit one invocation.
3. **Sign.** The batch hash is signed with an asymmetric key in AWS KMS (sign-only permission for the sealing job; the private key never leaves KMS).
4. **Anchor.** The batch record (header, root, batch hash, signature) is written to an S3 bucket in a separate AWS account in `ca-west-1` (Calgary), with Object Lock in compliance mode. Its retention is the longest the tenant's retention schedule requires, at least 7 years. Nobody can delete or overwrite these objects until retention ends, not even that account's root user. The anchor holds hashes and signatures only, no personal data.
5. **Customer copy.** Each day, the last batch hash and its signature are delivered to the tenant: downloadable in the admin portal, sent to the security contact, and, for OCAP® tenants, written to the tenant's own storage. The customer then holds independent proof that CanDo cannot alter.
6. **Verify.** The verifier recomputes each batch's root from the rows, checks the chain of batch hashes, the signatures and the anchored copies, and reports the first failing batch and the rows that differ. It also returns an **inclusion proof** for any single record (for example, "this change set existed by 15:00 on 18 October"). An auditor can check the proof with the published public key and an open-source script, without trusting CanDo.

The exact bytes are defined by `reference/audit_merkle_reference.py`. `tests/audit/merkle_vectors.json` holds the test vectors the production code must reproduce. CanDo does not use a blockchain: write-once storage, signatures and the customer's own copy give the same proof without putting any data, or even hashes, on a public network.

### Dedicated and OCAP® tenants

A tenant on its own Supabase project gets its own sealing job, signing key and anchor bucket, so its proof chain is independent of every other customer.

## 6. Application security

- OWASP ASVS level 2 as the baseline; dependency scanning (Dependabot), SAST (CodeQL) and secret scanning with push protection on GitHub.
- All SQL through Kysely or parameterized raw SQL; no string-built queries.
- File uploads: type allow-list, size limits, malware scan before the file is available (`16`, Q18), stored in private Supabase Storage buckets, served through short-lived presigned URLs after a permission check.
- Rate limits per user and per token (Workers rate limiting); webhook signatures; idempotency keys on POST; Cloudflare WAF in front of every public hostname.
- Secrets in Cloudflare Workers secrets and GitHub Environment secrets only; none in the repository, `.env` files committed, or an AI agent's context.
- Annual third-party penetration test; SOC 2 Type II and ISO 27001 programs from year one, relying on the providers' own reports for the infrastructure layer.
