# Reclaim — Product Definition

## Vision

South Africa has a growing, largely private gambling problem — sports betting, online
casinos, slots and crash games are all one tap away on a phone. **Reclaim** is a private,
non-judgemental companion that helps someone understand their gambling behaviour, protect
their money, resist urges, put real friction between an urge and the ability to gamble, and
work toward recovery at their own pace.

Reclaim is **not** a gambling application. It contains no odds, tips, predictions, gambling
news, casino-style games, affiliate links, or betting promotions, and it never will.

## Product principles

1. **Never shame the user.** Someone may install this app at the lowest point in their
   life. Every screen, notification and result communicates *"you can regain control"*,
   never *"you have failed."*
2. **Privacy is visible, not just implemented.** The user should feel, from the first
   screen, that this is a safe, private space — not a form to fill in for a third party.
3. **Friction over shame.** The product's job is not only to record gambling — it should
   make gambling *harder to act on* (blocking, cooling-off) while helping the user
   understand *why* the urge happened.
4. **Estimates are labelled as estimates.** Any "money saved"/"money kept" figure is a
   supportive estimate based on self-reported history, never presented as guaranteed fact.
5. **No casino-style gamification.** No spinning wheels, loot boxes, random rewards,
   gambling sounds or "jackpot" celebration effects anywhere in the product, including in
   how streaks/milestones are presented.
6. **Do not over-promise on blocking.** Android and iOS provide different, imperfect
   capabilities for blocking gambling content. Reclaim documents these limitations
   honestly (see `BLOCKING.md`) instead of claiming a guarantee it cannot keep.

## Target user

An adult in South Africa (18+) who gambles in a way that concerns them or someone close to
them — via sports betting apps, online casinos, slots or crash games — and who wants a
private way to understand and reduce that behaviour, with or without professional support.

## MVP feature set (Phase 1 — built now)

- Anonymous/local-first onboarding, with an optional account for backup and future
  accountability-partner support.
- Short, supportive onboarding questionnaire (gambling types, frequency, spend, triggers,
  goal: stop vs. reduce, what the money could go toward instead).
- Gambling self-assessment with a careful, non-diagnostic result (Low concern / Increasing
  risk / High risk) and recommended next actions.
- Recovery dashboard: days gambling-free, current/longest streak, estimated money kept,
  monthly deposited/withdrawn/net-loss summary, goals progress.
- Manual gambling loss/deposit tracker (deposit, withdrawal, win, loss, date, platform,
  gambling type, notes) with daily/weekly/monthly/lifetime totals. Wins are never
  celebrated.
- Recovery goals ("Car deposit: R8,400 / R20,000") tied to the estimated money kept.
- "I feel like gambling" urge-intervention flow: trigger selection → cooling-off timer →
  grounding/reasons-to-stop content → outcome logging.
- Bottom navigation scaffolded for all five sections (Home, Progress, Block, Journal,
  Support) so the information architecture doesn't need rework later; Block/Journal/
  Support show honest "coming soon" states in Phase 1 (see `ROADMAP.md`).
- Basic gambling-site blocking on Android (local on-device DNS filtering) and a
  build-ready-but-unverified iOS Screen-Time-based scaffold (no Mac available to test).
- Basic protection-lock duration selection with a cooling-off removal flow.

## Deliberately out of scope for Phase 1 (see `ROADMAP.md`)

Trigger journal insights, accountability partner, real support-organisation directory
content, push-notification delivery, remote blocklist sync UI, self-exclusion hub content,
and full bidirectional data sync are designed and documented but not built in this pass —
building all of them shallowly would leave nothing production-quality. `ROADMAP.md`
sequences them.

## Tone and language guidelines

- Prefer *"urge"*, *"session"*, *"recovery"* over clinical or alarmist language.
- Never use the words "addict"/"addiction" in UI copy directed at the user; refer to
  "problem gambling" or "gambling harm" only in third-person educational/support content.
- Notifications are always calm: *"You're doing well. Keep going."* — never alarms.
- Self-assessment results explicitly state they are not a medical diagnosis and recommend
  speaking to a professional for a fuller picture.
