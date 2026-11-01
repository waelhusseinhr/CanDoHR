# 12 · Smart assistant and in-product intelligence

**Requirement from the owner:** "Something that is really, really integrated and smart that can also help."

CanDo's intelligence has two layers:

- **Deterministic helpers.** They are always on and need no AI model: validation, consequences previews, explanations from calculation traces, reminders, data-quality nudges and anomaly rules. They are exact and testable.
- **The assistant.** It is optional and enabled per tenant. A language model answers questions, drafts documents and extracts rules, always within the user's permissions, and a person approves anything that changes data.

## 1. Principles

1. **Permission-aware.** The assistant acts as the signed-in user. It retrieves data only through the same API and permission checks the user has. It cannot see what the user cannot see.
2. **Proposes, never commits.** Any change the assistant suggests becomes a draft change set that the user reviews and submits. Hiring, pay, discipline and termination decisions are always made by people.
3. **Shows its sources.** Answers cite the records, rules and documents they used ("from TD1ON on file, signed 2026-01-08"; "agreement article 15.02").
4. **Residency.** Model calls go only to endpoints whose processing location meets the tenant's residency setting. If none is available, the assistant stays off.
5. **No training on customer data.** Prompts and outputs are not used to train models. Logs of assistant interactions follow the tenant's retention settings.
6. **Bias and fairness.** Recruitment and performance features are tested for disparate impact on a schedule, offer blind review, and are disclosed to applicants where law requires it (Ontario job postings that use AI screening must say so).

## 2. Deterministic helpers (release 1)

| Helper | Where | What it does |
| --- | --- | --- |
| Consequences preview | Every change set | Lists everything that will change (`05` §3) before approval |
| Paycheque explainer | Pay statement, payroll register | Turns the calculation trace into plain language: "Federal tax is $243.16 because annual taxable income is estimated at $64,462 …" |
| Net pay comparison | Pay statement | "Your net pay is $41.20 lower than last time because your CPP maximum was reset in January" |
| Pre-run validations | Payroll | Missing TD1, minimum wage breaches, negative net, inactive employees with pay, bank changes followed by large payments |
| Anomaly rules | Payroll, time | Period-over-period variance, outliers against peers, duplicate bank accounts |
| Reminders | All | Permit and certification expiry, probation end, funding end, step progression due, vacation that must be scheduled |
| Data quality | Core HR | Missing or stale fields by unit, with one-click fix forms |
| Smart defaults | Forms | Effective date defaults to the next pay period start; tax province from location; agreement from job and unit |

## 3. Assistant capabilities

| Capability | Example | Guardrails |
| --- | --- | --- |
| Ask the HRIS | "How many vacant positions in Public Works, and how long have they been open?" | Answers built from API queries the user may run; shows the query and links to the records |
| Explain | "Why did Ana's overtime change this period?" | Uses traces and change set history only |
| Do, with review | "Move the three inspectors to Building Services from 1 December" | Produces a draft change set with consequences; the user submits |
| Policy and agreement Q&A | "How much bereavement leave does a Local 0001 member get for a grandparent?" | Answers from the tenant's verified rules and documents, with article citations; says "not found" rather than guessing |
| Agreement extraction | Upload a PDF, get proposed rules | Every rule unverified until a specialist accepts it (`08` §4) |
| Drafting | Job descriptions (EN/FR), offer letters from templates, policy acknowledgements, ROE comments | Inclusive-language check; the user edits and approves |
| Forecasting | Headcount, overtime cost, retro cost of a proposed settlement | Labelled as estimates, with inputs shown |
| Employee help | "What will my vacation balance be on 15 July?" "How do I update my TD1?" | Self scope only |

## 4. Architecture

```
web chat panel ──► assistant service ──► tool calls (CanDo API as the user) ──► results
                         │                         ▲
                         └── model endpoint ───────┘ (residency-checked, no training)
```

- The assistant service exposes a fixed set of tools: `search_people`, `get_record`, `org_chart_as_of`, `explain_pay_result`, `resolve_rules`, `draft_change_set`, `search_documents`, `run_report`. Each tool calls the public API with the user's token.
- Retrieval of documents (policies, agreements) uses per-tenant embeddings stored in PostgreSQL (`pgvector`), filtered by the user's document permissions before ranking.
- Every assistant turn is logged with the tool calls made, so administrators can audit what was accessed.

## 5. Acceptance tests

1. A manager asks for an employee outside their subtree → the assistant says it cannot access that record.
2. "Give Ana a 10% raise" → a draft change set appears for review; nothing is committed.
3. "Explain my last pay" → every number in the explanation matches the stored trace.
4. Agreement Q&A with no matching clause → the answer says the agreement does not cover it and suggests contacting labour relations.
5. A tenant with Canada residency and no compliant model endpoint → the assistant panel is disabled, and deterministic helpers still work.
