# 13 · Screens and user experience

## 1. Portals and navigation

One web app with role-based portals. A user with several roles switches with a portal selector. The app is responsive, works on phones, and is fully usable by keyboard and screen reader (WCAG 2.1 AA). Each user picks the screen language (EN or FR) with the switch at the top, whatever the organization uses (`docs/22` §4).

| Portal | Home shows |
| --- | --- |
| Employee | Next pay date and last statement; leave balances as of today and a chosen date; tasks (acknowledge policy, update TD1); schedule; quick actions (request leave, update address, download T4) |
| Manager | Approvals waiting; team today (who's away, open shifts); team chart; vacancies and requisitions; alerts (probation ending, expiring certifications); team cost summary where permitted |
| HR | Change sets waiting; data-quality score; upcoming events (hires, terminations, leave returns); org chart with plans; cases |
| Payroll | Run calendar by pay group; current run status; exceptions; remittance calendar; rule edition in force; retro queue |
| Labour relations | Agreements and versions; verification queue; seniority lists; grievances |
| Admin | Users and roles; workflows; configuration bundles; integrations; audit |

Global elements: a search box (people, positions, units, documents) and an **as-of date control** that applies to every screen and is shown prominently when it is not today. An assistant panel appears where it is enabled, along with notifications and a language switch.

## 2. Screen inventory (release 1)

| Area | Screens |
| --- | --- |
| Core HR | People list; person profile (tabs: Overview, Job and assignments, Pay and payroll profile, Leave, Documents, History); position list and position detail; org units; org chart (`04`); jobs catalogue; locations; legal entities; change set inbox and detail; mass change wizard; imports |
| Recruitment and onboarding | Requisitions; postings; candidates pipeline; interview kits and scorecards; offers; onboarding checklists; probation reviews; status conversion |
| Payroll | Run calendar; run wizard (population → period and pay date → inputs → calculate → review → approve → release); employee result with trace; payroll register; exceptions; retro queue; off-cycle request; pay groups and calendars; earnings and deduction codes; remittances; year-end (PIER, slips, filing); ROEs; GL export; simulation |
| Compensation | Grids and ranges; merit cycle worksheets; pay equity analysis; total rewards statement |
| Benefits | Plans and classes; enrolment; life events; carrier files; premiums reconciliation |
| Time and leave | Schedule editor; open shifts; timesheets and approvals; leave requests and calendar; balances; holiday calendars; rule sets |
| Performance, learning, succession, engagement | Per module specs, built on the same list, detail and form patterns |
| Offboarding | Separation wizard (dates, reason, notice and severance calculation, final pay, ROE, access removal, assets); exit survey |
| Analytics | Dashboards; report builder with field-level security; scheduled reports |
| Compliance | Agreement library; verification queue; privacy requests; retention and legal holds; accessibility and equity reports |

## 3. Patterns every screen follows

- **Effective-dated edit:** every edit form starts with "Effective from" (default: next pay period start) and, for past dates, asks "new change or correction?" (`03` §4).
- **Consequences panel:** shows what else will change before saving.
- **History drawer:** on any record, every version with who, when, why, and a "view as of" link.
- **Explain button:** on any calculated number (pay, balance, entitlement), opens the trace.
- **Draft badge:** drafts and pending change sets are shown in a dashed outline, with an approval status chip.
- **Empty and error states:** written in plain language, with the next action.
- **The organization's own words:** job titles, position titles, names, documents and templates show exactly as the organization typed them, in the language it chose at setup. A word in the other language than the screen carries a small tag (*EN* or *FR*). Where the organization keeps a text in both languages, both fields are shown side by side. Quebec organizations keep their words in French. See `docs/22` §4.
- **Caution and acknowledgement:** when a user is about to go past a rule, the law or an agreement (for example overriding the seniority order, extending probation past the law's notice date, ending employment while a case is open), a dialog states what they are going past, in their screen language. To go ahead they tick "I have read this and I am going ahead on purpose", write the reason where one is needed, and confirm; the dialog shows if an approval is still needed. What was shown, who acknowledged and when are kept and appear in the history drawer. See `docs/23` §2.1.
- **Reminders:** dated reminders (an offer expiring, a probation decision due, a legal due date, a union notice to send) appear in the task list and by notification, and need no acknowledgement.

## 4. Design system

Radix primitives and in-house components. The design tokens include color, spacing, type, focus and motion, with light and dark themes and a high-contrast mode. Key components: data table (virtualized, column chooser, saved views, CSV export within permissions), effective-date picker, person picker (scope-aware), money input (CAD, locale formats), org chart canvas, timeline, consequences list, approval chip, trace viewer.

## 5. Mobile

Responsive web plus an installable web app with offline punches (queued with the original timestamp), approvals, leave requests, pay statements and schedule. Biometric sign-in comes through the device's passkey.
