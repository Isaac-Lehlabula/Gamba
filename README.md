# Reclaim

A private, non-judgemental mobile app that helps people in South Africa reduce or stop
problematic gambling — recovery tracking, urge intervention, financial awareness, goals,
and platform-appropriate gambling-site blocking. **Reclaim is not a gambling app**: no
odds, tips, casino games, affiliate links or betting promotions.

See `docs/PRODUCT.md` for the full product definition and `docs/ROADMAP.md` for what's
built vs. planned.

## Repository layout

```
/mobile          Flutter app (Android + iOS)
/backend         ASP.NET Core Web API (Reclaim.sln)
/infrastructure  Local dev infrastructure (docker-compose.yml for Postgres + pgAdmin)
/docs            Product, architecture, database, API, blocking, security, privacy, roadmap docs
```

## Getting started

### 1. Start local infrastructure

```powershell
cd infrastructure
docker compose up -d
```

Postgres will be available at `localhost:5437` (db `reclaim`, user `reclaim`, password
`reclaim_dev_password` — local dev only, see `backend/README.md` for how production
configuration works). pgAdmin is available at `http://localhost:5051`.

### 2. Run the backend

```powershell
cd backend
dotnet restore
dotnet ef database update --project src/Reclaim.Infrastructure --startup-project src/Reclaim.Api
dotnet run --project src/Reclaim.Api
```

The API listens on `https://localhost:5001` (see `backend/src/Reclaim.Api/Properties/launchSettings.json`).
Swagger UI is available at `/swagger` in Development.

### 3. Run the mobile app

```powershell
cd mobile
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter run
```

By default the app runs fully offline/anonymous — no backend connection is required to
use onboarding, the dashboard, the tracker, goals or the urge-intervention flow. Creating
an account (Settings → Back up my data) connects to the backend at the URL configured in
`mobile/lib/core/network/api_config.dart` (defaults to `10.0.2.2:5001` for the Android
emulator talking to a locally-running backend).

## Documentation

- [`docs/PRODUCT.md`](docs/PRODUCT.md) — vision, principles, MVP scope
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — backend + mobile architecture
- [`docs/DATABASE.md`](docs/DATABASE.md) — schema design
- [`docs/API.md`](docs/API.md) — API specification
- [`docs/BLOCKING.md`](docs/BLOCKING.md) — Android/iOS gambling-site blocking research & design
- [`docs/SECURITY.md`](docs/SECURITY.md) — security measures
- [`docs/PRIVACY.md`](docs/PRIVACY.md) — POPIA considerations
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — phased plan
