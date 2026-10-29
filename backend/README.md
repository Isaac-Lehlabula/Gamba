# Reclaim backend

ASP.NET Core 10 Web API. See `../docs/ARCHITECTURE.md` for the layering rules.

```
src/Reclaim.Domain           entities and domain rules (no dependencies)
src/Reclaim.Application      use-case handlers, request/response contracts, validators, interfaces
src/Reclaim.Infrastructure   EF Core (Postgres), repositories, password hashing, JWT, audit, jobs
src/Reclaim.Api              controllers, auth, error handling, rate limiting, Program.cs
tests/Reclaim.Application.Tests      handler/domain/validator unit tests (in-memory fakes)
tests/Reclaim.Api.IntegrationTests   full API tests against a Testcontainers Postgres
```

## Running locally

```powershell
cd ../infrastructure; docker compose up -d postgres; cd ../backend
dotnet ef database update --project src/Reclaim.Infrastructure --startup-project src/Reclaim.Api
dotnet run --project src/Reclaim.Api --launch-profile https
```

Swagger UI: `https://localhost:5001/swagger`. Health: `https://localhost:5001/api/v1/health`.

## Configuration and secrets

No secrets are committed. Settings come from `appsettings.json`, then environment variables
(`Jwt__SigningKey`, `Audit__IpHashKey`, `ConnectionStrings__Reclaim`, ...).

| Setting | Notes |
|---|---|
| `ConnectionStrings:Reclaim` | Development points at the docker-compose Postgres on port 5438 |
| `Jwt:SigningKey` | HMAC-SHA256 key, at least 32 bytes. **Required outside Development** — startup fails without it |
| `Audit:IpHashKey` | HMAC key for hashing client IPs in the audit log, at least 32 characters. Required outside Development |
| `FieldEncryption:ActiveKeyId`, `FieldEncryption:Keys:<id>` | AES-256 keys (base64, 32 bytes) for encrypted free-text columns. Development uses a committed dev-only key; production must supply its own. Keep old keys listed after rotating |
| `PasswordHashing:Iterations` | PBKDF2 work factor, default 600,000 |
| `AccountDeletion:GracePeriodDays` | Default 7 |
| `RateLimiting:*` | Per-IP auth limit and per-user API limit, per minute |

In Development, if `Jwt:SigningKey` or `Audit:IpHashKey` is missing, the API generates a random
one at startup, so a fresh clone runs with no setup; tokens stop working when it restarts. To
keep sessions across restarts, set your own:

```powershell
dotnet user-secrets set "Jwt:SigningKey" "<at least 32 random bytes>" --project src/Reclaim.Api
```

## Tests

```powershell
dotnet test Reclaim.slnx
```

The integration tests need Docker running (Testcontainers starts a throwaway Postgres); without
Docker they are reported as skipped, not failed.

## Adding a migration

```powershell
$env:ASPNETCORE_ENVIRONMENT="Development"
dotnet ef migrations add <Name> --project src/Reclaim.Infrastructure --startup-project src/Reclaim.Api --output-dir Persistence/Migrations
```
