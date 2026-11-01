# Reclaim — Roadmap

## Phase 1 — this implementation pass

Infrastructure, auth, onboarding, self-assessment, recovery dashboard, loss tracker,
goals, urge intervention flow, Android blocker (working), iOS blocker (written,
unverified — no Mac available), basic protection lock (local), support-resource stub.
Full detail in `PRODUCT.md`.

Progress:

- [x] Backend foundation: solution layering, EF Core + Postgres, ProblemDetails errors,
      FluentValidation, Serilog, rate limiting, health check, Swagger (dev)
- [x] Auth: register, login, refresh rotation with reuse detection, logout, account
      deletion with 7-day grace period and background hard-delete; audit log
- [x] Profile: `GET`/`PUT /profile`
- [x] Onboarding responses, self-assessment (questions, scoring, guidance, history)
- [x] Gambling entries: CRUD, filters, per-profile platforms, stats by local period;
      sensitive free text encrypted at rest
- [ ] Backend: goals, urges, dashboard, blocklist, support resources
- [x] Mobile foundation: encrypted local database, theme, router with onboarding gate,
      five-tab shell (Block, Journal and Support show honest "coming soon" screens)
- [x] Mobile: onboarding questionnaire, offline self-assessment with result and history
- [x] Mobile: loss tracker (add/edit/delete, period totals) and recovery dashboard
      (days without gambling, longest run, estimated money kept, this month's totals)
- [x] Mobile: "I feel like gambling" urge flow (trigger, intensity, 10-60 minute pause that
      survives closing the app, personal reasons and trigger-specific tips, breathing and
      grounding, outcome; an urge that ends in gambling counts toward the streak)
- [x] Mobile: recovery goals with contributions ("set aside" or moved from the estimated
      savings, which is capped at the current estimate and always labelled as an estimate)
- [x] Mobile: settings (app lock with PIN/biometrics, edit plan, delete everything), optional
      account with one-shot backup (`POST /api/v1/backup`)
- [x] Backend: urges, goals, dashboard summary, public blocklist (seeded), verified-only
      support resources, backup endpoint
- [x] Android blocker: local VPN DNS filter, verified on an emulator (Android 16): listed
      domains and their subdomains stop resolving, other sites resolve normally, the Block
      tab shows blocked attempts, and turning it off restores normal lookups. Protection lock
      with 24-hour cooling-off and user-added sites are local-only for now
- [ ] iOS Screen Time scaffold written in AppDelegate.swift, unverified (needs a Mac), off
      unless built with RECLAIM_IOS_SCREEN_TIME=true
- [ ] Mobile: a notification when a pause finishes while the app is closed (needs the
      Phase 6 notification work)
- [ ] Android blocker, iOS blocker scaffold, local protection lock

## Phase 2 — trigger journal & insights (done)

Built in the app (local-first) and the backend (`/journal-entries`, `/journal-entries/insights`),
with matching insight rules tested on both sides.

- Full trigger journal (mood/trigger/intensity/what-helped) with descriptive, clearly
  non-diagnostic pattern surfacing ("Most of your recorded urges happen between 20:00 and
  23:00.").
- Recovery timeline screen (Day 1 → Day 3 → 1 week → ... → 1 year) with calm, non-gamified
  milestone visuals.
- `GET /journal-entries/insights` backend implementation.

## Phase 3 — blocker hardening & protection lock backend

- Move Protection Lock and its cooling-off removal request fully server-side (currently
  local-only in Phase 1) so it survives app reinstall/device change for account users.
- Blocklist admin/back-office workflow for curating `BlocklistDomain` without redeploying
  the API.
- Android: recently-blocked-attempts log surfaced in-app; investigate TLS SNI inspection
  as a defence-in-depth layer beyond DNS-only filtering (documented limitation in
  `BLOCKING.md`).
- iOS: verify the `FamilyControls`/`ManagedSettings` implementation on a real Mac + device,
  request the Family Controls **distribution** entitlement early (lead time: days to
  weeks), and build the required Shield Configuration/Shield Action extensions with the
  App Group-based handoff pattern.

## Phase 4 — accountability partner

- Trusted-contact invitation flow, PIN-gated check-ins, opt-in detailed-history sharing,
  protection-setting-change approval flow. Strong emphasis on consent UX per `PRIVACY.md`.

## Phase 5 — support & self-exclusion hub

- Real, verified South African support-organisation directory (gambling support lines,
  counselling, financial counselling, emergency numbers) sourced and verified before
  publishing — not hardcoded speculatively.
- Self-exclusion guidance content, clearly scoped to *information*, not a claim that
  Reclaim performs legal self-exclusion on the user's behalf, unless/until an official
  integration exists with a South African self-exclusion scheme.

## Phase 6 — sync, notifications, polish

- Real bidirectional incremental sync engine with conflict resolution (Phase 1 ships a
  manual one-shot backup push only).
- Push notification delivery (milestones, daily check-in, goal progress, protection
  status, cooling-off reminders) with the discreet-wording toggle honoured end-to-end.
- Accessibility pass (screen reader labelling, dynamic type, contrast audit).
- CI pipeline (GitHub Actions: `dotnet test`, `flutter test`, build artifacts).

## Explicitly deferred / needs further validation before building

- `NEURLFilter` (iOS 26+) as a stronger iOS blocking layer once PIR server infra and
  Apple's OHTTP relay onboarding are justified by scale.
- Bank/transaction-detection integration (explicitly optional per the product brief; not
  required for MVP and raises additional POPIA/financial-data-sharing considerations that
  need dedicated legal review before design).
- Cross-border hosting decision, pending the POPIA section 72 review noted in
  `PRIVACY.md`.
- Formal adoption of a validated clinical screening instrument (e.g. PGSI-style scoring)
  with appropriate licensing/clinical sign-off, replacing Phase 1's own non-diagnostic
  assessment wording.
