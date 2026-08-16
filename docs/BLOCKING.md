# Reclaim — Gambling Website/App Blocking: Research & Design

This document is written **before** any blocking code, per the product brief's
requirement to document platform capabilities honestly before implementing them. Android
and iOS do **not** provide equivalent capabilities. Nothing in this document, or in the
product's marketing/UI copy, should claim a blocking guarantee neither platform can
actually provide.

## Summary of the decision

| Platform | Mechanism chosen for MVP | Status |
|---|---|---|
| Android | `VpnService`-based local, on-device DNS filtering | Implemented, buildable & testable now |
| iOS | `FamilyControls` + `ManagedSettings` (Apple "Screen Time API"), `.individual` authorization | Written now; requires a Mac + Xcode + paid Apple Developer account to build/test/ship |

Mechanisms considered and **rejected** for MVP, with reasons, are listed at the end of this
document.

## Android: what Android allows

Android has no public "block this domain system-wide" API for regular apps without root.
The realistic, no-root approach used by mature tools (e.g. the open-source NetGuard) is:

1. The app implements `android.net.VpnService` and establishes a local VPN interface
   (`TUN`) whose only job is to capture the device's DNS traffic (`addRoute` targeting the
   configured DNS server IPs, or all traffic with a fast passthrough for non-DNS packets).
2. Incoming UDP/TCP port-53 packets are parsed as DNS queries (RFC 1035). The requested
   domain is compared against the local (backend-synced) blocklist.
3. If blocked: the app responds with `0.0.0.0` (or `NXDOMAIN`), so the requesting app/
   browser cannot resolve the gambling domain and the connection fails before it starts.
4. If not blocked: the query is forwarded untouched to the real upstream DNS resolver and
   the response is relayed back.

**Required permissions / setup:** `BIND_VPN_SERVICE`, a one-time system VPN-permission
dialog (`VpnService.prepare()`), a persistent notification while the local VPN is active
(required by Android), and — for Play Store distribution — completing Google Play's
**VpnService declaration form**, selecting a permitted core-purpose category (device
security / network tools fits Reclaim), documenting the usage in the store listing, and
encrypting any data that leaves the device.

**Play Store restrictions:**
- Only one `VpnService` may be active per device; if the user runs a "real" VPN app at the
  same time, ours is displaced (and vice versa) — the UI must detect and surface this.
- Google requires the VPN's purpose to match a declared, permitted category and forbids
  using the capability to intercept/redirect traffic for any purpose beyond what is
  declared (no ad injection, no traffic resale, no analytics beyond blocking).
- The always-on VPN notification is unavoidable — this is a deliberate Android
  transparency measure, not something we can hide, and is actually useful here (it makes
  protection visibly "on").

**Limitations we document to the user, not hide:**
- Apps/browsers using **DNS-over-HTTPS/DNS-over-TLS** (bypassing the device's normal DNS
  resolution) or **hardcoded IP addresses** are not filtered by this mechanism.
- A determined user can disable the VPN toggle in system settings at any time — this is
  why the Protection Lock feature adds a *behavioural* cooling-off barrier on top, not a
  technical one Android cannot provide.
- This is DNS-level filtering, not full URL filtering — blocking is per-domain, not
  per-path.

**Security implications:** the VPN tunnel is local (loops back to the device's own DNS
resolution), never proxies user traffic to our servers, and only DNS lookups (which
domains, not payloads) pass through the service. This is disclosed to the user before
activation.

## iOS: what iOS allows

iOS provides **no VPN-based option that is realistic for a consumer self-blocking app**:
`NEDNSProxyProvider`/`NEFilterDataProvider` (Network Extension content filters) exist but
are effectively designed around supervised/MDM-managed devices for non-trivial deployment,
and Apple's newest `NEURLFilter` (iOS 26+) requires standing up a Private Information
Retrieval (PIR) + Bloom-filter server infrastructure and getting Apple's Oblivious HTTP
relay approved for production — appropriate for a well-resourced parental-control vendor,
not an MVP.

The mechanism real shipping **self**-control apps use (One Sec, Opal, Freedom) is Apple's
**Screen Time API**: three frameworks working together.

1. **`FamilyControls`** — call
   `AuthorizationCenter.shared.requestAuthorization(for: .individual)`. Unlike the
   parental-control flavour, `.individual` authorization is for the device's own owner,
   authenticated with Face ID/Touch ID/passcode, and does **not** impose iCloud
   sign-out/app-deletion restrictions on the user.
2. **`ManagedSettings`** — the enforcement layer, via a `ManagedSettingsStore`:
   - `store.webContent.blockedByFilter = .specific(Set<WebDomain>, exceptions: Set<WebDomain>)`
     blocks a **string-based list of domains** (`WebDomain(domain:)`, no picker needed)
     inside WebKit-based browsing. Because Apple requires all iOS browsers to use WebKit,
     this applies to Safari and third-party browsers alike, not just Safari. **This is the
     mechanism that maps directly onto our remotely-updatable gambling-domain blocklist.**
   - `store.shield.applications` shields specific installed apps at the OS level (a
     full-screen block that persists through force-quit and reboot, removable only by our
     app clearing the setting). Apple only exposes **opaque tokens** for apps — the user
     must select which installed gambling apps to shield via the system
     `FamilyActivityPicker`; we cannot scriptably target "any betting app" by name.
3. **`DeviceActivity`** — an app-extension used for scheduling/monitoring; not required
   for a simple always-on shield, but documented for the roadmap (e.g. re-applying a
   shield automatically).

**Required entitlements / approval — the critical constraint:** the
`com.apple.developer.family-controls` **development** entitlement is available to any
paid Apple Developer account immediately, so the feature can be built and tested on a
real device right away. The **distribution** entitlement, required before the app can go
to TestFlight or the App Store, must be **requested separately from Apple for the main app
bundle ID and for every app extension bundle ID**, via
`https://developer.apple.com/contact/request/family-controls-distribution`, and approval
has historically taken from a few business days to a few weeks. This must be requested
early once a paid Apple Developer account exists — it is on the critical path for shipping,
not something that can be done the week of submission.

**App Store restrictions:** Apple reviews Family Controls apps manually and expects a
genuine self-control/digital-wellbeing use case (which Reclaim clearly has); using the
entitlement for anything else (e.g. general analytics) would risk rejection.

**Limitations we document to the user, not hide:**
- Web-content blocking only covers WebKit-based web browsing, not arbitrary in-app
  browsers that render content without WebKit or gambling apps' own native networking —
  a native gambling *app* must be shielded via `shield.applications` instead, which
  requires the user to actively pick it via the system picker (friction, but not
  automatic).
- The user (as the device owner, not a managed child) can, at any time, open Reclaim and
  turn the shield off, or revoke Reclaim's Family Controls authorization in system
  Settings — iOS gives the account owner ultimate control by design. Protection Lock's
  cooling-off period is our behavioural mitigation for this, clearly described as such.
- Cannot be verified end-to-end until this project has access to a Mac + Xcode + a paid
  Apple Developer account with the distribution entitlement approved.

## What "Protection" honestly means as a result

Given the above, Reclaim never claims blocking is unbypassable. The in-app copy (see
`ProtectionLock` feature) says, in effect: *"Reclaim makes gambling sites and apps harder
to reach and adds a waiting period before protection can be turned off. It cannot
guarantee you can never bypass this on your own device — no consumer app can — but it is
designed to interrupt the moment of urge."* This is intentional and matches the product
principle of never over-promising.

## Remote blocklist architecture

Both platforms consume the same backend-managed list (`BlocklistDomain`, `GET
/api/v1/blocklist?since=...`), so newly identified gambling domains can be pushed without
an app release:
- Android's `VpnService` filter reloads its in-memory domain set from the local Drift
  cache, which syncs from `/blocklist` on a schedule and on app foreground.
- iOS re-applies `webContent.blockedByFilter` with the updated domain set whenever the
  synced list changes (from the main app, since the shield configuration extension has
  strict memory/runtime limits and should not do network I/O itself).

## Alternatives considered and rejected for MVP

- **`NEURLFilter` (iOS 26+):** most privacy-preserving and most "system-wide" of Apple's
  options, but requires operating PIR/Bloom-filter server infrastructure and passing
  Apple's OHTTP relay onboarding for production use — disproportionate for an MVP; revisit
  once the product has scale and dedicated infra investment (`ROADMAP.md`).
- **`NEDNSProxyProvider`/`NEFilterDataProvider` (iOS):** mature APIs, but oriented around
  supervised/MDM deployment for reliable non-Safari coverage; a personal, non-managed
  device does not get the same guarantees, per Apple's own engineers on the Developer
  Forums.
- **Root-based Android hosts-file blocking:** would require root, which the overwhelming
  majority of users don't have and which Play Store policy effectively precludes for a
  mainstream consumer app.
- **DNS-over-HTTPS provider swap (Android/iOS system DNS settings):** would require the
  user to manually configure a custom DoH resolver we operate — a valid *complementary*
  defence-in-depth option worth adding later, but it is easily undone by the user or by
  apps that hardcode their own DNS/IP, so it does not replace the in-app blocker.
