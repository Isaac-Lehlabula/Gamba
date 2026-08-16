# Reclaim — Security

Reclaim handles highly sensitive personal information (gambling behaviour, finances,
mental-health-adjacent journal content). Security is treated as a first-class requirement,
not an afterthought.

## Authentication & session security

- Passwords hashed with a modern adaptive algorithm (BCrypt/ASP.NET Core Identity's
  `PasswordHasher`, work factor tuned per environment); never stored or logged in plain
  text.
- JWT access tokens are short-lived (15 minutes). Refresh tokens are long-lived (30 days),
  **stored server-side only as a salted hash**, single-use, and rotated on every refresh.
  Reusing an already-rotated refresh token revokes the entire token family (theft
  detection) and is written to `AuditLog`.
- Mobile stores tokens exclusively in `flutter_secure_storage` (Android Keystore / iOS
  Keychain-backed) — never in plain SharedPreferences/`NSUserDefaults` or Drift.
- Optional app-level lock (biometric via `local_auth`, PIN fallback) gates app content
  even when the OS session is otherwise unlocked, so a shared/borrowed phone doesn't
  expose the app.

## Transport & API security

- HTTPS is mandatory; HTTP requests are rejected/redirected. HSTS enabled in production.
- All inputs validated server-side with FluentValidation regardless of client-side
  validation; the API never trusts client-computed aggregates (e.g. streaks, totals) as
  input — those are recomputed server-side from source records.
- Authorization: every endpoint enforces that the authenticated user can only read/write
  their own resources (resource-owner checks in application handlers, not just controller
  attributes).
- Rate limiting: strict per-IP limits on `/auth/register`, `/auth/login`, `/auth/refresh`
  (e.g. fixed-window limiter) to blunt credential stuffing/brute force; per-user limits on
  the rest of the authenticated API to blunt abuse/scraping.
- Global exception handling middleware ensures stack traces/internal exception details
  never reach a client response; a correlation id is returned instead and the full detail
  is logged server-side.

## Data-at-rest protection

- **Backend:** PostgreSQL with disk-level encryption expected at the hosting layer
  (documented as an infra requirement); sensitive free-text fields (journal notes, urge
  notes, gambling-entry notes) are stored encrypted at the application layer using a
  server-held key (envelope encryption pattern), separate from the transport-level
  protections above, so a raw DB dump does not expose journal content in plain text.
- **Mobile:** the Drift/SQLite database is encrypted at rest via `sqlcipher_flutter_libs`;
  the database encryption key itself lives in secure OS-backed storage
  (`flutter_secure_storage`), never in the database or app preferences.
- Secrets (DB connection strings, JWT signing key, encryption keys) are never committed to
  source control. Local development uses `dotnet user-secrets`/`.env` files (gitignored);
  production is documented to use a managed secrets store (e.g. Key Vault/Parameter
  Store equivalent) — this repo ships environment-variable-driven configuration so any of
  those can be wired in without code changes.

## Logging & audit

- Structured logging (Serilog) never logs: passwords, tokens, journal/urge free-text
  content, or full gambling-entry notes. Only ids, types, timestamps and outcome enums are
  logged for operational visibility.
- `AuditLog` captures security-relevant events (login, logout, password change, refresh
  reuse detection, account-deletion request, protection-lock removal request/cancel) with
  a hashed IP address, never the raw journal/financial content.

## Data minimisation & deletion

- Anonymous/local mode collects **no** personal identifiers at all — everything lives
  on-device.
- Account creation collects only an email and password; display name and other profile
  fields are optional.
- Account deletion (`DELETE /auth/account`) starts a short grace period (soft-delete on
  `AppUser`), after which a background job **hard-deletes** the user and all associated
  rows (cascade), consistent with the POPIA principles in `PRIVACY.md`. Local on-device
  data can be wiped immediately and independently from Settings, with no server round-trip
  required.

## Dependency & infrastructure hygiene

- Docker Compose is used for local Postgres so no developer runs a shared/production
  database locally.
- `dotnet test`/`flutter test` are run as part of the standard workflow before considering
  a feature complete; CI wiring (GitHub Actions) is a near-term roadmap item so this is
  enforced automatically rather than by convention alone.
