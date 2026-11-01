# Reclaim — API Specification

Base path: `/api/v1`. All endpoints (except `/auth/register`, `/auth/login`,
`/auth/refresh`, `/blocklist`, `/support/resources`, `/health`) require a valid JWT bearer
access token. Responses use `application/json`; errors use RFC 7807 `ProblemDetails`.

Legend: **[P1]** implemented in this pass, **[P2]** specified here but deferred (see
`ROADMAP.md`).

## Auth **[P1]**

| Method | Route | Notes |
|---|---|---|
| POST | `/auth/register` | email + password → creates `AppUser`, returns access+refresh token |
| POST | `/auth/login` | email + password → access+refresh token |
| POST | `/auth/refresh` | refresh token → new access+refresh token pair (rotation) |
| POST | `/auth/logout` | revokes the presented refresh token |
| DELETE | `/auth/account` | starts the account-deletion grace period (see `SECURITY.md`) |

## Profile & onboarding **[P1]**

| Method | Route | Notes |
|---|---|---|
| GET | `/profile` | current user's profile |
| PUT | `/profile` | update display name, recovery goal type, start date |
| POST | `/onboarding-responses` | submit onboarding questionnaire answers |
| GET | `/onboarding-responses` | fetch the latest submitted answers |

## Self-assessment **[P1]**

| Method | Route | Notes |
|---|---|---|
| GET | `/assessment/questions` | the questionnaire (versioned) and answer scale; anonymous, so the app can show it before an account exists |
| POST | `/assessment/submit` | `{ answers: { questionId: 0-3 } }` → score + risk level + recommended actions + disclaimer. Every question must be answered; score and level are always computed server-side |
| GET | `/assessment/history` | past results, newest first |

## Dashboard **[P1]**

| Method | Route | Notes |
|---|---|---|
| GET | `/dashboard/summary` | `?timeZone=` (default `Africa/Johannesburg`) → `streaks` (`current`, `longest`, `journeyDay`; null until the profile has a start date), `thisMonth` totals, `usualMonthlySpend`, `estimatedMoneyKept` (null without a usual spend), `goals` snapshot. Computed from source records with the same rules as the app; deposits, losses, wins and urges ending in gambling count as gambling days, withdrawals don't |

## Gambling entries (loss tracker) **[P1]**

| Method | Route | Notes |
|---|---|---|
| GET | `/gambling-entries` | query `from`, `to` (both inclusive, on `occurredAtUtc`), `entryType`, `gamblingType`, `platform` (name, case-insensitive), paginated, newest first |
| POST | `/gambling-entries` | create an entry |
| PUT | `/gambling-entries/{id}` | edit an entry |
| DELETE | `/gambling-entries/{id}` | remove an entry |
| GET | `/gambling-entries/stats` | `?timeZone=` (IANA, default `Africa/Johannesburg`) → today / this week (from Monday) / this month / lifetime: `deposited`, `withdrawn`, `won`, `lost`, `netLoss` |

Entries take a free-text `platformName`; the backend groups names case-insensitively per
profile. `netLoss = (deposited − withdrawn) + (lost − won)`: people usually log either money
moved or outcomes, and the app should explain that logging both for the same money counts it
twice. A negative `netLoss` means the user is ahead.

## Goals **[P1]**

| Method | Route | Notes |
|---|---|---|
| GET | `/goals` | list, oldest first, each with `savedAmount` and its `contributions` |
| POST | `/goals` | create: `name`, `category` (EmergencyFund, Car, HouseDeposit, Debt, Holiday, Education, Family, Savings, Custom), `targetAmount`, optional `targetDateUtc` |
| PUT | `/goals/{id}` | edit |
| DELETE | `/goals/{id}` | remove, with its contributions |
| POST | `/goals/{id}/contributions` | `amount`, `source` (`Manual` or `EstimatedSavings`), optional `occurredAtUtc` |
| DELETE | `/goals/{id}/contributions/{contributionId}` | remove a contribution |

## Urges **[P1]**

| Method | Route | Notes |
|---|---|---|
| POST | `/urges` | start: `trigger`, optional `intensity` (1-5), `coolingOffMinutes` (10, 20, 30 or 60), optional `startedAtUtc` |
| PUT | `/urges/{id}/extend` | add 10 minutes to an unresolved pause |
| PUT | `/urges/{id}/resolve` | `outcome` (Passed, Gambled, Abandoned), optional `notes` (encrypted at rest) and `resolvedAtUtc`; once only |
| GET | `/urges` | history, newest first, paginated |

## Support resources **[P1, read-only content]**

| Method | Route | Notes |
|---|---|---|
| GET | `/support/resources` | anonymous. Only rows a person has marked verified are ever returned; the list is empty until real contacts are checked and added |

## Blocklist **[P1 endpoint, P2 client enforcement richness]**

| Method | Route | Notes |
|---|---|---|
| GET | `/blocklist?since={timestamp}` | anonymous. Without `since`: every active domain. With it: every change after it, deactivations included, so clients can unblock too. Returns `items` (`domain`, `category`, `isActive`, `updatedAtUtc`) and `nextSince` to pass back next time. A starter list is seeded at startup from `Infrastructure/Seed/blocklist-seed.txt` |

## Backup **[P1]**

| Method | Route | Notes |
|---|---|---|
| POST | `/backup` | everything on the phone in one request (profile, onboarding responses, assessments, entries, urges, goals with contributions, journal entries). Matches on client ids: creates what's missing, updates what's there, skips ids owned by another account. Safe to repeat; never deletes. Returns `created`, `updated`, `skipped` |

## Journal **[P2, implemented]**

| Method | Route | Notes |
|---|---|---|
| GET/POST/PUT/DELETE | `/journal-entries` | `occurredAtUtc`, optional `mood` (1-5), `trigger`, `urgeIntensity` (1-5), `outcome` (NoUrge, Resisted, Gambled), `helped` (Walked, TalkedToSomeone, Breathing, Distraction, BlockedSites, LeftPhone, RememberedGoal, Other), `note` (encrypted at rest). An entry needs at least one of these |
| GET | `/journal-entries/insights` | `?timeZone=` → `insights` (plain sentences), `urgesRecorded`, `minimumUrges` (5), `disclaimer`. Combines journal urges with completed urge sessions. Rules: busiest 3-hour window if it holds ≥40% (and ≥3); busiest weekday if ≥30% of ≥7 urges; most-recorded trigger if ≥30% of ≥4 with a trigger; most common "what helped" among urges got through, if ≥2. Same rules and wording as the app (`mobile/lib/features/journal/domain/insights.dart`) |

## Protection lock **[P2 backend; P1 ships a local-only version on-device]**

| Method | Route | Notes |
|---|---|---|
| GET | `/protection/status` | current lock state |
| POST | `/protection/lock` | start a lock for a fixed duration |
| POST | `/protection/removal-request` | starts a 24h cooling-off removal request |
| DELETE | `/protection/removal-request/{id}` | cancel a pending removal request |

## Custom blocked domains **[P2 backend sync; P1 local-only]**

| Method | Route | Notes |
|---|---|---|
| GET/POST/DELETE | `/custom-domains` | user-added domains, subject to `Removable` while protection is locked |

## Trusted contacts (accountability partner) **[P2]**

| Method | Route | Notes |
|---|---|---|
| GET/POST/DELETE | `/trusted-contacts` | invite/list/revoke |
| POST | `/trusted-contacts/{id}/check-in` | request/record a check-in |

## Notification preferences **[P2 backend; P1 local device settings]**

| Method | Route | Notes |
|---|---|---|
| GET/PUT | `/notifications/preferences` | toggle categories, discreet wording |

## Conventions

- All list endpoints support `page`/`pageSize` and return `{ items, page, pageSize,
  totalCount }`.
- All monetary values are `decimal` ZAR, serialised as JSON numbers with 2 decimal places.
- All timestamps are ISO-8601 UTC. A timestamp sent without an offset is read as UTC.
- Create endpoints for user records (onboarding responses, assessments, gambling entries)
  accept an optional client-generated `id`, so records created offline keep their identity
  when synced. Reusing an existing id returns `409`.
- Required enum fields that are missing fail validation rather than defaulting.
- Mutating endpoints validate via FluentValidation before reaching a handler; validation
  failures return `400` with a `ProblemDetails` body listing field errors.
- Rate limiting: `/auth/*` endpoints are limited per-IP (see `SECURITY.md`); all other
  authenticated endpoints are limited per-user.
