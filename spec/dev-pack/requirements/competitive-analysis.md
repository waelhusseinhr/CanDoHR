# CanDo HRIS — Competitive Analysis

Oct 17, 2026 · @Wael

The platforms that handle every Canadian edge case (Dayforce, ADP, UKG, Workday) are built and priced for large employers, while the SMB tools each cover only part of it. CanDo's opening is to cover every Canadian jurisdiction, Quebec, unions and public-sector agreements, s.87, grant funding and compliance programs natively, for employers of every size: from 25 employees to municipalities, provincial agencies and First Nations governments with tens of thousands.

## Vendors reviewed

Fifteen platforms sold to Canadian employers, from enterprise suites to Canadian SMB specialists. Facts are from vendor pages and independent reviews opened in October 2026.

| Vendor | Ownership and base | Best fit | Canadian payroll | What stands out |
| --- | --- | --- | --- | --- |
| [Dayforce](https://www.consulting.ca/news/5172/deloitte-acquires-bdos-dayforce-practice) (formerly Ceridian) | Toronto and Minneapolis; taken private by Thoma Bravo on 4 February 2026 | Mid-market to enterprise | Native | Single platform for HR, payroll, workforce management and talent; chosen by the Government of Canada for HR and pay |
| [ADP Workforce Now](https://www.adp.ca/en/what-we-offer/products-by-name/adp-workforce-now/payroll.aspx) | US parent with Canadian operations | Mid-size to large | Native | Full suite; French options for Bill 96; built-in error detection and real-time gross-to-net |
| [UKG Pro](https://themuse.com/jobs/ukg/payroll-compliance-advisor-6357e2) | US, private; Canadian compliance team in Toronto and Montreal | Large unionized, 24/7 and public-sector employers | Native | Workforce management heritage (Kronos); UKG Pro Workforce Management used by municipalities such as the [City of Hamilton](https://jobera.com/job/cityofhamilton-job-id-32091-payroll-lead-enterprise-time-and-attendance-system-0a87257e/); about 950 jobs cut in April 2026 |
| [Workday](https://auditfriendly.co/software/humi) | US | Large enterprise | Native in a handful of countries, Canada included | Deepest agent platform in the category |
| [Rippling](https://www.rippling.com/blog/rippling-launch-canada) | US, with a Toronto team | Growing SMB to mid-market | Native | HR, IT and finance on one employee record; modules priced separately |
| [HiBob](https://briefglance.com/companies/hibob/pulses/18133) | Israel and US; Toronto office opened 13 May 2026 | Mid-size, fast-growing companies | None native: payroll only in the US and UK; Canada through Payroll Hub sync to ADP Workforce Now | Strong employee experience, performance and analytics; Bob Finance available in Canada |
| [BambooHR](https://erpresearch.com/erp-add-ons/hcm-extensions/bamboohr) | US (Utah) | SMB with lean HR teams | None: payroll is US-only | Strong usability, built-in ATS, Mercer pay benchmarks, Bamboo AI |
| [Sparkrock](https://go.sparkrock.com/sparkrock-media-kit) | Mississauga; part of Edsembli | Non-profits, human services, K-12 | Native | ERP on Microsoft Dynamics 365 Business Central: finance, HR, payroll, scheduling, union rules |
| [Humi by Employment Hero](https://auditfriendly.co/software/humi) | Australian parent since January 2025 | 11–200 employees | Native; Quebec on a separate product | [Section 87 support](https://employmenthero.com/en-ca/blog/section-87-indian-act-payroll-guide/) added in 2026; HR data on AWS in Australia and Canada |
| [Payworks](https://www.capterra.ca/software/1017911/payworks) | Winnipeg | 11–1,000, service-first | Native, Canada only | Dedicated payroll rep; real-time payroll and benefits link; no public API or AI |
| [Collage](https://amm.mb.ca/wp-content/uploads/2025/06/Collage-HR-Offering-Overview.pdf) | Toronto; People Corporation | SMB under 1,000 | Native, or sync to Dayforce, ADP, Payworks, Wagepoint, Desjardins, Nethris | Benefits-broker connected; insurer integrations with Canada Life, Manulife, Sun Life and others |
| [Folks](https://news.marketersmedia.com/folks-keeps-canadian-employee-data-hosted-owned-and-compliant-in-canada/89195953) | Quebec City | 11–1,000, Canada only | Native | All data hosted in Canada; SOC 2 Type 2; aligned with Law 25; bilingual |
| [Nethris / Employer D](https://nethris.com/?p=32926) | Montreal; Employer D through Desjardins | SMB, Quebec, construction | Native | CCQ-approved construction payroll; bilingual |
| [Rise](https://risepeople.com/?p=48194) | Vancouver | 20–250 employees; non-profits and Indigenous organizations | Native | Payroll by program and funding source; tax-exempt pay for eligible employees |
| [Wagepoint](https://auditfriendly.co/software/humi) | Canadian | Micro and small business | Native, payroll-first | Most transparent pricing; files RL-1 slips but not the RL-1 summary |

The same fifteen vendors are in the interactive [CanDo Vendor Explorer](https://claude.ai/artifact/RFLT6phVob9B2BuBotcv3G): filter by segment, compare up to three against CanDo's target across 14 capabilities, and switch to the module or jurisdiction views.

**Earlier project comparison.** The project file *Talent Acquisition System Vendor Comparison* scored CanDo's recruitment design against SAP SuccessFactors, Oracle Recruiting, ADP, Dayforce, Sparkrock, Deel, BambooHR and UKG Pro. Three things in it are now superseded: it placed CanDo at 500+ employees with limited small-business focus (CanDo now targets every size), its CanDo scores were design intentions rather than evidence, and it gave no sources. Two points still hold and are carried into this review: collective agreement support was the clearest gap among the SMB tools (Deel and BambooHR scored none), and its 3–6 month implementation estimate for CanDo is a useful target against 4–8 months for Dayforce and 6–12 for SAP and Oracle. SAP SuccessFactors, Oracle and Deel are not in the table above because Canadian employers rarely choose them for Canadian payroll; they matter for multinationals and would return in a Europe review.

## Positioning

&#91;embedded content: positioning · 15 vendors and CanDo's target, our assessment\]

The top-right incumbents carry enterprise pricing and months-long implementations; the Canadian specialists in the bottom right each cover part of the rules with narrower suites.

## Module coverage

Core HR, payroll and time are table stakes; compensation planning, succession, analytics and compliance case management are where the SMB tools thin out. The vendor-by-vendor grid is in the interactive explorer.

| CanDo module | What most vendors offer | Where the market is thin | CanDo stance |
| --- | --- | --- | --- |
| [01 Core HR & Position Management](https://claude.ai/code/artifact/ca4bed22-b3a1-4549-a5ac-9934a5f1738f) | Employee records, org chart, self-service | Position control and effective-dated history outside enterprise suites | Match enterprise depth at SMB scale |
| [02 Recruitment & Onboarding](https://claude.ai/code/artifact/f6131748-b7c8-46c6-8eb3-2e5dcfdd8dab) | ATS and onboarding in most suites; Humi shipped an AI screening agent in March 2026 | Union posting rules, Ontario 2026 posting rules, Indigenous hiring programs | Lead on compliant hiring |
| [03 Payroll](https://claude.ai/code/artifact/d011fb3d-a712-479d-ba65-b7691351feab) | Native Canadian payroll everywhere except BambooHR | Quebec in one product with the rest of Canada; s.87 with correct CPP and EI handling; collective agreement retro pay | Match the specialists, lead on unions and s.87 |
| [04 Compensation](https://claude.ai/code/artifact/0f41dea6-45ac-4a0f-aa81-bd7675391cfc) | Enterprise suites; BambooHR with Mercer data | Market pricing, pay equity and pay transparency reporting in Canadian SMB tools | Lead |
| [05 Benefits](https://claude.ai/code/artifact/67101c5b-b593-4e11-a956-0b33ed310804) | Collage and Humi connect to carriers; Payworks links payroll and benefits in real time | Flex and spending accounts with Quebec taxability | Match Collage on carriers |
| [06 Time, Attendance & Leave](https://claude.ai/code/artifact/1304ea74-8afc-4410-bddb-7a79cac14a9b) | Time off everywhere; scheduling in Dayforce, Sparkrock, Rise | Union overtime offering by seniority, statutory leave rules per province | Lead on rules depth |
| [07 Performance](https://claude.ai/code/artifact/942b1f47-9c2a-4603-9db2-d8c13bd0f6fb) | Reviews and goals in mid-tier plans | Unionized and Indigenous-specific review options | Match, with fairness checks |
| [08 Learning](https://claude.ai/code/artifact/9a2e4ade-3fec-4830-a9b6-300a86c62e8c) | LMS in Humi Premium, Rippling, ADP, Dayforce | Canadian compliance training rules and the Quebec 1% training law | Lead on compliance training |
| [09 Succession & Workforce Planning](https://claude.ai/code/artifact/da62c350-42f6-4abd-b7ea-4a123f0e1f4f) | Workday and Dayforce | Almost absent below enterprise | Lightweight version for SMBs |
| [10 Engagement & Recognition](https://claude.ai/code/artifact/1dcdb23a-2376-4cd8-ae9b-73c7f0962cdc) | Surveys in BambooHR; chat in Humi; many use add-ons | Recognition tax limits tracked for payroll | Match |
| [11 Offboarding & Separation](https://claude.ai/code/artifact/50fe8480-bfe1-42dd-8b20-8885c55f5440) | Checklists and ROE filing (Humi files within one business day) | Notice, severance and group termination calculators by province | Lead |
| [12 Analytics & Reporting](https://claude.ai/code/artifact/4810dacb-5139-4e76-b4f9-91f6917c6fb1) | Strong in enterprise suites; lighter in Collage and Rise | Statutory report catalogue; equity analysis with suppression | Match, plus statutory catalogue |
| [13 Compliance, Labour Relations & Privacy](https://claude.ai/code/artifact/50447648-8362-4f6e-b443-b8be8b216f3a) | Rarely in an HRIS; usually spreadsheets or separate EHS and case tools | Accommodation, OHS, investigations, grievances in one system | Clearest gap to lead |

## Canadian capability benchmark

Each Canadian requirement has a vendor that sets the bar; none of the SMB tools sets it on all of them.

| Capability | Who sets the bar | What CanDo must do |
| --- | --- | --- |
| Quebec payroll and French | Nethris (CCQ-approved construction payroll); Humi files RL-1 and handles QPP, QPIP and CNESST, but on a separate Quebec product; ADP markets French options for Bill 96; Wagepoint does not file the RL-1 summary | One product for Quebec and the rest of Canada, RL-1 slips and summary, French-first interface option |
| Section 87 (Indian Act) | Employment Hero records exemptions once and applies them each run; Rise configures tax-exempt pay | TD1-IN capture, connecting-factor record, exempt portion by pay period, CPP election, EI always deducted ([CRA](https://www.canada.ca/en/revenue-agency/news/cra-multimedia-library/businesses-video-gallery/payroll-section-87-first-nations-workforces.html)), T4 reporting codes |
| Unionized workforces | Sparkrock (union rules), Dayforce and ADP; Humi is rated weaker for heavily unionized employers | Wage grids, seniority, overtime offering by seniority, retro pay after ratification, grievances |
| Non-profit funding | Sparkrock (finance and payroll in one ERP); Rise (payroll by program and funding source) | Grant allocation by percentage or hours, funding end-date alerts, funder reports, no ERP required |
| Data residency and sovereignty | Folks hosts all data in Canada with SOC 2 Type 2; Humi moved HR data to AWS in Australia and Canada; US-owned vendors remain reachable under the US CLOUD Act even with Canadian hosting | Canadian hosting for all data and backups, Canadian ownership as a stated commitment, Law 25 assessment support |
| Pay transparency and AI disclosure | Not a stated feature of the vendors reviewed | Ontario 2026 and BC posting rules enforced at posting time; AI-use statement generated |
| Benefits carriers | Collage integrates with Canada Life, Manulife, Sun Life, Equitable and others | Carrier enrolment files and invoice reconciliation |
| Service model | Payworks assigns a dedicated payroll rep; Humi and Payworks sell managed payroll tiers | Self-serve plus a managed payroll option and an implementation partner network |
| Open API and AI agents | Workday leads; ADP ships agents; Humi's API is read-mostly with no payroll scope; Payworks has no public API | Full API with payroll scopes, a first-party MCP server, AI guardrails aligned with Law 25 |

## Pricing signals

Single modules start near $7–10 per employee per month; full suites stack to several times that, and the enterprise suites publish nothing. Published, simple bundle pricing is itself a differentiator, since Humi moved its HR plans to quote-only after the Employment Hero acquisition.

| Vendor | Published or reported price | Basis |
| --- | --- | --- |
| BambooHR | Core US$10, Pro US$17, Elite US$25 per employee per month; flat from US$250 a month at 25 or fewer employees; payroll and benefits are US-only add-ons | Published ([ERP Research](https://erpresearch.com/erp-add-ons/hcm-extensions/bamboohr)) |
| Rippling | From about US$8 per employee per month plus a US$35–40 monthly base; each further module adds its own per-employee fee | Vendor references reported by third parties ([Gusto guide](https://gusto.com/resources/guides/switch-payroll-providers/rippling-pricing)) |
| Collage | HR $10 per employee (minimum $100 a month); benefits $3; payroll $9; payroll sync $3; managed payroll $30; free implementation | 2025 Canadian offer sheet ([PDF](https://amm.mb.ca/wp-content/uploads/2025/06/Collage-HR-Offering-Overview.pdf)) |
| Humi by Employment Hero | Payroll CA$7 per employee (CA$70 minimum); managed payroll CA$30 (CA$500 minimum); HR plans quote-only with 10-user minimum; all-in reported at CA$19–49 | Published payroll; all-in unverified ([Audit Friendly](https://auditfriendly.co/software/humi)) |
| Wagepoint | CA$20 a month plus CA$4 per employee (Solo); CA$40 plus CA$6 (Unlimited) | Published, reported by [Audit Friendly](https://auditfriendly.co/software/humi) |
| Payworks | CA$23 per pay run plus CA$2.65 per employee (payroll list price); other modules on quote | Reported by [Audit Friendly](https://auditfriendly.co/software/humi) |
| ADP, Dayforce, Workday, Sparkrock, Folks, Nethris, Rise | Quote only | Vendor sites and listings |

CanDo's pricing model is still an open decision in Module 00; these figures are what small and mid-sized buyers compare against, while large and public-sector buyers compare quote-based enterprise pricing and implementation cost.

## Where CanDo wins

&#91;embedded content: differentiation · goal, three pillars, foundation\]

Each pillar answers a named rival: Canadian depth answers HiBob, BambooHR and Rippling; unions and public sector answer UKG and Dayforce on their home ground; trust and compliance answer everyone, since no vendor reviewed offers HR case management with Canadian hosting and ownership.

## Gaps to close and threats

Five items are high priority: two are openings CanDo can own now (one product for all of Canada including Quebec, and compliance case management), three are races already under way (Indigenous payroll, data sovereignty, AI agents). Priority and status are dropdowns to update as decisions land.

| Item | Type | Priority | CanDo response | Modules | Status |
| --- | --- | --- | --- | --- | --- |
| Quebec runs on a separate product at Humi; Wagepoint skips the RL-1 summary | Opportunity | High | One product for Quebec and the rest of Canada, RL-1 slips and summary | 03 | In spec |
| SMB HRIS tools leave accommodation, OHS, investigations and grievances to spreadsheets | Opportunity | High | Module 13 case management as a headline feature | 13 | In spec |
| Employment Hero and Rise now market Indigenous payroll and s.87 support | Threat | High | Full s.87 workflow plus Indigenous governance options (OCAP®) and cultural leave | 01, 03, 06 | In spec |
| Canadian hosting and ownership are now buying criteria (Folks leads with them) | Threat | High | Canadian hosting incl. backups, SOC 2 Type II, Law 25 assessment kit, Canadian ownership commitment | 00, 13 | In spec |
| Workday, ADP and Dayforce are shipping AI agents; Humi has a recruitment agent | Threat | High | Payroll-scoped API, first-party MCP server, explainable AI with human approval | 00, 12 | Not started |
| Collage sells through a benefits broker network (People Corporation) | Threat | Medium | Broker and advisor partner program; carrier integrations | 05 | Not started |
| Embedded payroll engines (Nmbr behind Collage Payroll) lower the bar for HR-only vendors | Threat | Medium | Decide build versus embed for the calculation engine | 00, 03 | Not started |
| Payworks and Humi win on service with dedicated reps and managed payroll | Gap | Medium | Managed payroll tier and certified implementation partners | 00 | Not started |
| Humi's HR pricing became quote-only with minimums | Opportunity | Medium | Publish simple bundle pricing | 00 | In spec |
| Dayforce, now private-equity owned, may push down-market | Threat | Low | Weeks to implement for mid-sized employers; phased rollouts with parallel runs for large ones | 00 | Not started |
| UKG and Dayforce own unionized, 24/7 and municipal time-to-pay (UKG Pro Workforce Management at the City of Hamilton) | Threat | High | Union and 24/7 scheduling rules at their depth, driven by the agreement library | 06, 13 | In spec |
| No vendor reviewed imports agreements from Negotech and provincial registries into rules | Opportunity | High | Collective agreement library with verified rules and renewal monitoring | 13, 01, 03 | In spec |
| HiBob opened a Toronto office in May 2026 but has no native Canadian payroll | Threat | Medium | Match its employee experience; lead with native payroll and agreements | 07, 10, 03 | In spec |

## Improvements made to the module specs

Every module was revised on 17–18 October 2026 to cover all employer sizes, the public sector, all 14 jurisdictions and the findings above; each ends with a "How CanDo compares" section and a dated review note.

| Module | Main additions |
| --- | --- |
| [00 Master Platform Overview](https://claude.ai/code/artifact/02ecaf37-f9cb-436e-be4d-92fa2f7695f2) | New segments (enterprise, municipal, provincial, First Nations governments); jurisdiction scope; government integration diagram; enterprise scale targets; Quebec assessment; Europe readiness |
| [01 Core HR](https://claude.ai/code/artifact/ca4bed22-b3a1-4549-a5ac-9934a5f1738f) | Public-sector governance, shared services, non-employee person types, scale |
| [02 Recruitment & Onboarding](https://claude.ai/code/artifact/f6131748-b7c8-46c6-8eb3-2e5dcfdd8dab) | 2026 hiring rules by jurisdiction; public-sector competitions and mass hiring |
| [03 Payroll](https://claude.ai/code/artifact/d011fb3d-a712-479d-ba65-b7691351feab) | 14-jurisdiction table; CRA and Revenu Québec documents; 2026 values; public-sector payroll; s.87 EI correction; Europe in place of US |
| [04 Compensation](https://claude.ai/code/artifact/0f41dea6-45ac-4a0f-aa81-bd7675391cfc) | Grids at scale, government frameworks, salary disclosure, bargaining costing |
| [05 Benefits](https://claude.ai/code/artifact/67101c5b-b593-4e11-a956-0b33ed310804) | Public-sector pension plans, union trusts, self-insured plans, northern benefits |
| [06 Time, Attendance & Leave](https://claude.ai/code/artifact/1304ea74-8afc-4410-bddb-7a79cac14a9b) | Overtime and holidays for all 14 jurisdictions; 24/7 and public-sector scheduling |
| [07 Performance](https://claude.ai/code/artifact/942b1f47-9c2a-4603-9db2-d8c13bd0f6fb) | Agreement-aware reviews, senior official evaluation, scale |
| [08 Learning](https://claude.ai/code/artifact/9a2e4ade-3fec-4830-a9b6-300a86c62e8c) | Credentials tied to scheduling, elected official training, remote delivery |
| [09 Succession & Workforce Planning](https://claude.ai/code/artifact/da62c350-42f6-4abd-b7ea-4a123f0e1f4f) | Statutory positions, retirement waves, complement and bargaining scenarios |
| [10 Engagement & Recognition](https://claude.ai/code/artifact/1dcdb23a-2376-4cd8-ae9b-73c7f0962cdc) | Frontline reach, union coordination, access-to-information safe surveys |
| [11 Offboarding & Separation](https://claude.ai/code/artifact/50fe8480-bfe1-42dd-8b20-8885c55f5440) | Notice for the remaining nine jurisdictions; workforce adjustment and pension options |
| [12 Analytics & Reporting](https://claude.ai/code/artifact/4810dacb-5139-4e76-b4f9-91f6917c6fb1) | Salary disclosure, council, Statistics Canada, audit and funder reporting |
| [13 Compliance, Labour Relations & Privacy](https://claude.ai/code/artifact/50447648-8362-4f6e-b443-b8be8b216f3a) | Collective agreement library with diagram; public-sector obligations; First Nations jurisdiction |

## Sources

Opened or searched 17–18 October 2026. Third-party prices are labelled as such in the tables; confirm with each vendor before quoting them.

- [Audit Friendly: Humi review](https://auditfriendly.co/software/humi) (Humi, Payworks, Wagepoint, Workday comparisons and prices)
- [ERP Research: BambooHR](https://erpresearch.com/erp-add-ons/hcm-extensions/bamboohr)
- [Collage HR offering overview (2025)](https://amm.mb.ca/wp-content/uploads/2025/06/Collage-HR-Offering-Overview.pdf)
- [Rippling: launch in Canada](https://www.rippling.com/blog/rippling-launch-canada) and [Gusto guide to Rippling pricing](https://gusto.com/resources/guides/switch-payroll-providers/rippling-pricing)
- [Consulting.ca: Deloitte acquires BDO's Dayforce practice](https://www.consulting.ca/news/5172/deloitte-acquires-bdos-dayforce-practice) and [BetaKit on the Thoma Bravo deal](https://betakit.com/canadian-led-dayforce-to-be-acquired-by-thoma-bravo/)
- [ADP Canada: Workforce Now payroll](https://www.adp.ca/en/what-we-offer/products-by-name/adp-workforce-now/payroll.aspx)
- [Sparkrock media kit](https://go.sparkrock.com/sparkrock-media-kit)
- [Folks data residency announcement](https://news.marketersmedia.com/folks-keeps-canadian-employee-data-hosted-owned-and-compliant-in-canada/89195953)
- [Nethris: CCQ-approved payroll provider](https://nethris.com/?p=32926)
- [Rise: Indigenous organizations](https://risepeople.com/?p=48194) and [non-profits](https://risepeople.com/solutions/industry/non-profits/)
- [Employment Hero: Section 87 guide](https://employmenthero.com/en-ca/blog/section-87-indian-act-payroll-guide/)
- [HiBob Toronto office](https://briefglance.com/companies/hibob/pulses/18133) and [HiBob native payroll countries](https://www.omnihr.co/faqs/hibob-vs-bamboohr-faq-2)
- [UKG Canadian payroll compliance role](https://themuse.com/jobs/ukg/payroll-compliance-advisor-6357e2), [City of Hamilton UKG Pro WFM role](https://jobera.com/job/cityofhamilton-job-id-32091-payroll-lead-enterprise-time-and-attendance-system-0a87257e/) and [UKG April 2026 job cuts](https://stlawyers.ca/blog-news/ukg-job-cuts-april-2026/)
- [Negotech](https://negotech.service.canada.ca/search/index.html) and [U of T list of collective agreement databases](https://cirhr.library.utoronto.ca/research/collective-agreements)
- [CRA: Section 87 and First Nations workforces](https://www.canada.ca/en/revenue-agency/news/cra-multimedia-library/businesses-video-gallery/payroll-section-87-first-nations-workforces.html)
