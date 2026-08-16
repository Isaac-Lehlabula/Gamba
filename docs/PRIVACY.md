# Reclaim — Privacy & POPIA Considerations

Reclaim is designed privacy-by-design: the least amount of identifying data is collected,
by default nothing leaves the device, and every piece of sensitive data collected has a
clear, user-facing purpose.

## Why POPIA matters here

South Africa's Protection of Personal Information Act 4 of 2013 (POPIA) regulates how
"responsible parties" process personal information about data subjects. Gambling
behaviour, urges and journal content are closely tied to a person's mental and financial
wellbeing. While POPIA's definition of **"special personal information"** (section 26)
lists categories such as health, and does not name "gambling behaviour" explicitly, this
project treats journal/urge/assessment content **as if it were special personal
information**, out of an abundance of caution and because the self-assessment result
(risk level) is arguably health-adjacent information. This is a deliberately conservative
interpretation.

## Lawful basis for processing

- **Explicit, specific, voluntary, informed consent** (POPIA section 11 read with section
  27(1)(a)) is the lawful basis used throughout. Onboarding presents a clear, plain-language
  explanation of what is collected, why, and that it is optional, before any account or
  sensitive data is captured — never a buried legal document as the only disclosure.
- Consent is granular: using the app anonymously requires no consent flow beyond basic
  terms; creating an account and enabling sync/accountability features each have their own
  explicit opt-in.
- The user can withdraw consent at any time via account/data deletion (`SECURITY.md`).

## Data minimisation in practice

- No government ID numbers, no physical address, no financial account numbers are ever
  collected. Financial *amounts* the user chooses to log are the only "financial" data
  point, entered manually.
- Email is the only identifier required for an account; a display name is optional.
- The self-assessment and onboarding questionnaire are optional — a user can use the
  tracker/urge/dashboard features without ever answering them.
- Analytics/telemetry, if added later, must be aggregate/anonymised by default and is out
  of scope for Phase 1 entirely (no analytics SDK is included in this build).

## Security safeguards (section 19 of POPIA)

See `SECURITY.md` for the concrete technical/organisational measures: encryption at rest
and in transit, hashed credentials/tokens, access control, audit logging, and secure
secrets management. These directly satisfy POPIA's section 19 requirement to secure the
integrity and confidentiality of personal information.

## Cross-border processing

If backend hosting infrastructure is ever located outside South Africa, POPIA section 72
requires one of: the data subject's consent, a binding agreement ensuring an equivalent
level of protection, or the destination having comparable data-protection laws. This must
be revisited before choosing a hosting region for production and is tracked in
`ROADMAP.md`.

## Data subject rights supported

- **Access:** a user can view all data collected about them via the app itself (dashboard,
  tracker, journal, assessment history) — there is no hidden server-side data not visible
  to the user.
- **Correction:** all logged entries (gambling entries, goals, profile) are editable.
- **Deletion:** account deletion is self-service (`DELETE /auth/account`), starts a short
  grace period, then hard-deletes; local-only data can be wiped instantly and entirely
  on-device without any server interaction.
- **Objection/withdrawal:** optional features (sync, accountability partner, notifications)
  can each be disabled independently at any time.

## Third parties

- The **trusted contact / accountability partner** feature is opt-in and, by default,
  shares no detailed gambling history — only high-level check-in status — unless the user
  explicitly enables detailed sharing (`TrustedContact.SharesDetailedHistory`). This is a
  privacy-by-design default, not an afterthought toggle.
- Support-resource listings link out to third-party organisations; no data is shared with
  them automatically by tapping a resource.

## What this document is not

This is an engineering-facing privacy design summary, not a substitute for a legal
Privacy Policy or a formal Data Protection Impact Assessment, and not legal advice. Before
a real public launch, a qualified South African privacy/legal professional should review
the final data flows, the consent copy, and whether an application to the Information
Regulator under section 27(2) is prudent given the final feature set.
