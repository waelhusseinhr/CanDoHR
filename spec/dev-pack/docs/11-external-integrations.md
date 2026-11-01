# 11 · External integrations

Every external integration is an **adapter** in `packages/modules/<module>/adapters/`, with one interface, a sandbox implementation for tests, and the real implementation. Government file formats change every year, so their schemas are downloaded from the publisher at build time and validated in CI. They are never typed from memory.

## 1. Government

| Integration | Direction | Format and channel | Spec to implement against | Notes |
| --- | --- | --- | --- | --- |
| CRA T4, T4A slips and summaries | Out | XML, filed by Internet File Transfer, with a T619 transmittal | CRA [XML specifications](https://www.canada.ca/en/revenue-agency/services/e-services/filing-information-returns-electronically-t4-t5-other-types-returns-overview/xml-specs.html) for the tax year (T619 2026, T4 2026, T4A 2026) | Electronic filing mandatory for more than 5 slips of a type. All returns in one submission must be the same type. Remove empty optional tags. Amendments use the amendment report type. |
| CRA remittances | Out | Payment through the customer's bank or CRA My Business Account; CanDo produces the remittance amounts, voucher data and due dates | T4001 | CanDo does not move money to CRA itself in release 1 |
| ROE Web | Out | XML payroll extract, uploaded by the employer in ROE Web (up to 10 files at once) | Service Canada ROE Web user requirements, Appendix D (payroll extract XML, version 2.0) | Business number with RP suffix; block 15C pay period earnings; block 17 other monies; amendments. Issue within Service Canada's deadline after the pay period with the interruption. |
| Revenu Québec | Out | RL-1 XML, remittances | Revenu Québec software requirements (IN-412-V), RL-1 guide | Phase 2; annual certification by 1 February |
| Workers' compensation boards | Out | Board-specific returns (many accept online forms or files) | Each board's employer filing spec | Release 1: reports with the figures each board's annual return asks for |
| Employer health tax and levies | Out | Annual return figures; instalments | Provincial guides | Reports in release 1 |
| NT and NU payroll tax | Out | Remittance figures and annual return | Territorial guides | Reports in release 1 |
| Job Bank | Out | Job posting feed | ESDC Job Bank | Through the recruitment posting adapter |
| Negotech and provincial agreement registries | In | Download of agreement PDFs | Registry websites | Manual upload is always available |

## 2. Banks and payments

| Integration | Format | Notes |
| --- | --- | --- |
| Direct deposit | Payments Canada CPA Standard 005 (fixed-width AFT, 1464-byte logical records), or ISO 20022 `pain.001` where the customer's bank accepts it | Each bank publishes its own variant (originator ID, file creation number, data centre). Adapter per bank, configured with the bank's spec sheet and tested with a test file before go-live. |
| Positive pay (cheques) | Bank-specific CSV or fixed-width | |
| Bank returns and NSFs | Return file or manual entry | Reissue workflow |
| Pre-notification | Zero-dollar prenote where supported | |

Bank files are created only from approved runs, signed with a checksum, released under dual control, and stored with control totals.

## 3. Identity and collaboration

| Integration | Standard |
| --- | --- |
| Single sign-on | OIDC, SAML 2.0 |
| Provisioning | SCIM 2.0 (users, groups) to Microsoft Entra ID, Okta, Google Workspace |
| Calendar | Microsoft Graph, Google Calendar (interviews, leave on calendars) |
| Messaging | Microsoft Teams, Slack (approvals and notifications through bots) |
| E-signature | DocuSign, Adobe Acrobat Sign |

## 4. Finance and benefits

| Integration | Format |
| --- | --- |
| GL journals | CSV and API adapters for QuickBooks Online, Xero, Sage Intacct, Microsoft Dynamics 365 Business Central, NetSuite, SAP, Oracle; generic mapped CSV |
| Benefits carriers | Eligibility files (carrier-specific CSV or fixed-width; standard 834 where a carrier uses it); premium reconciliation |
| Pension plans | Contribution and member data files for OMERS, HOOPP, LAPP, BC Municipal Pension Plan and others, per each plan's file spec |
| Group RRSP and TFSA providers | Contribution files |
| Union dues | Remittance report per local |

## 5. Recruitment

Job boards (Indeed, LinkedIn, Job Bank, IndigenousWorks and others) through XML feeds or partner APIs; background checks and assessments through vendor APIs with status webhooks; video interview tools; the career site as part of CanDo.

## 6. CanDo's own API

`api/openapi.yaml` is the contract. Rules:

- REST over HTTPS, JSON, versioned by URL (`/v1`).
- OAuth 2.0 client credentials for integrations; authorization code with PKCE for apps; scopes per module and action.
- Every read accepts `asOf`. Every write goes through `/v1/change-sets` or a module endpoint that creates a change set internally.
- `Idempotency-Key` header on POST.
- Cursor pagination; `fields` selection; ETags.
- Bulk endpoints for imports, run as jobs, with validation reports.
- Webhooks per `05` §5.
- Sandbox tenant with synthetic data for every customer.

## 7. Adapter contract

```ts
interface FilingAdapter<TInput, TReceipt> {
  validate(input: TInput): Promise<ValidationReport>;   // against the downloaded schema
  render(input: TInput): Promise<FileArtifact>;          // bytes + filename + checksum
  submit?(file: FileArtifact): Promise<TReceipt>;        // only where an API exists
  parseResponse?(raw: Buffer): Promise<TReceipt>;        // acknowledgements, errors
}
```

Every adapter has golden-file tests: a fixed input produces a byte-identical file, which is reviewed once against the spec and then frozen.
