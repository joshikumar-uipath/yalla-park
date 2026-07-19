# Yalla Park (DXB Park)

**Never get a Dubai parking fine because you forgot to pay.**

A native iOS app that knows the moment you walk away from your car, tells you instantly whether the spot is free or paid, and puts the official Parkin payment one thumb-tap away — then keeps defending you with reminders, a lock-screen countdown, and one-tap extensions until you drive off.

- **App Store Connect:** "Yalla Park" · bundle `com.avjoshi.dxbpark` · currently on TestFlight (0.2.0)
- **Stack:** SwiftUI · iOS 17+ · SwiftData · no backend, no accounts — everything stays on the phone

---

## 1. The problem

Paid parking in Dubai (Parkin zones) runs **Monday–Saturday, 8:00 AM – 10:00 PM** (Sundays and public holidays free). Payment itself is easy — an SMS to **7275** with `PLATE ZONE HOURS` — but *remembering* is the hard part, and the failure mode is expensive:

- You park, you're mid-conversation or rushing to a meeting, and the SMS never gets sent → **AED 150+ fine**.
- You park at 9 PM when it's free, forget the car overnight, and enforcement starts at 8 AM → fine.
- You paid for 2 hours, lunch runs long, the session silently expires → fine.
- You're new to a street and don't know the zone code, so you "do it later" → fine.

The official Parkin app and Apple Maps solve *paying* and *navigating*. Neither solves **forgetting**. This app competes on exactly one axis: **it catches the fine before it happens.**

## 2. The core insight (how it knows you parked)

iOS doesn't let apps monitor Bluetooth in the background, so the app can't detect "user left the car" by itself. The trigger lives *outside* the app:

> An **iOS Shortcuts Personal Automation** — *"When my car's Bluetooth disconnects → Open URL `dxbpark://parked`"* — fires the instant you switch off the engine and walk out of range. iOS opens Yalla Park on the parked screen, which already knows roughly where you are.

The app's entire job is the **8 seconds after that URL fires**. For users who skip the automation, the same flow starts from the home-screen widget, the lock-screen widget, or "Hey Siri, I just parked."

## 3. How it solves it — the four defense layers

The product is a stack of four independent defenses; any one of them alone prevents the fine:

| # | Layer | What happens |
|---|-------|--------------|
| 1 | **Instant trigger** | Car Bluetooth disconnects → app opens itself with the verdict ready: *"Paid zone — pay before you go"* or *"You're free to walk away."* |
| 2 | **Two-tap payment** | Pre-filled SMS composer to Parkin's 7275 (`PLATE ZONE HOURS`). You literally just press Send. iOS requires that one tap — everything else is automated. |
| 3 | **Free-now-paid-later reminder** | Parked at night or on Sunday when it's free? The app schedules a morning notification (default 15 min before the 8 AM enforcement start): *"Zone 444A starts charging at 8 AM — pay now?"* |
| 4 | **Nag + expiry watch** | Dismissed the screen without paying in a paid zone? A reminder fires 5 minutes later. Paid session running? Notifications at 10 minutes before and at expiry, each with a one-tap **+1 hour** action. |

A one-tap **"I'm not parking here"** kills every scheduled nag for false triggers (drop-offs, passengers).

**The honesty rule (trust moat):** iOS won't let the app read the confirmation SMS back from Parkin, so it *cannot* verify payment. It never pretends to — after the composer closes it asks once, *"Did you send it?"*, and only a user-confirmed session is ever shown as Paid.

## 4. Features

### Shipped (M1–M4, TestFlight builds 1–2)

**The parked screen (Home)**
- Warm-light map UI with your car pinned, area name, and a bottom verdict sheet
- Four states: paid-zone-pay-now / paid-zone-but-which-zone (manual entry + recent-zone chips) / free-right-now (with "we'll remind you at 7:45" chip) / active-session countdown
- Duration picker (1–3 hrs), live cost estimate (~AED/hr by zone band), plate pulled from Settings
- Zone memory: past spots are matched by location (~40 m radius) and auto-fill their zone code

**The rules engine (`ParkinRules.swift`)**
- Free/paid verdict as a pure function of date/time and zone kind — Mon–Sat 08:00–22:00 paid, Sundays free, Asia/Dubai timezone
- All domain rules (SMS number, message format, tariffs, paid windows) live in one config file
- 15 boundary unit tests (07:59 vs 08:00, 21:59 vs 22:00, Saturday↔Sunday midnight rollovers)

**Notifications (the layers 3–4 machinery)**
- Morning free→paid reminder, 5-minute unpaid nag, expiry −10 min and at-expiry alerts with a **+1 hour** action button that works from the lock screen
- A `syncProtection()` reconciler runs on every state change so exactly the right notifications are scheduled and stale ones are cancelled

**Glanceable surfaces**
- **Live Activity + Dynamic Island:** a real parking meter on the lock screen — zone, live countdown, progress bar; compact Dynamic Island shows time remaining
- **Home-screen widget:** "I just parked" button when idle; a **live countdown meter** (zone, timer, progress bar, tap-to-extend) while a session runs, reverting automatically at expiry
- **Lock-screen circular widget:** compact countdown while parked
- **Siri / App Shortcuts:** "Hey Siri, I just parked" and "Hey Siri, extend my parking"

**Session & spots**
- Full-screen pass card (coral gradient, countdown, zone, plate) — your "ticket"
- Extend flow: +1 hour re-sends the SMS and rolls the session, Live Activity, and widget forward
- My Spots: automatic history of where you park, times parked, last parked
- Onboarding with plate setup and an illustrated Shortcut-automation walkthrough, plus a "Finish setup" banner until the automation fires for real the first time

**Privacy by architecture**
- No backend, no account, no analytics. One-shot location only when you park, "while using" permission. The marketing line — *"your location never leaves your phone"* — is literally true.

### Remaining (M5 roadmap)
- Arabic localization + full RTL
- Accessibility pass (Dynamic Type, VoiceOver through the whole parked flow)
- Wallet-style pkpass / richer pass sharing
- My Spots map view with photos & notes ("Level 3, Bay 214, near lift B")
- Onboarding polish; WhatsApp payment path (Parkin's Mahboub bot, +971 58 800 9090) as secondary
- Android version with true auto-SMS (no composer tap needed) — longer-term

## 5. Architecture at a glance

```
Shortcuts automation ──dxbpark://parked──▶ AppRouter ──▶ HomeView.runPipeline()
                                                            │
                     ┌──────────────┬─────────────────┬─────┴──────────┐
                     ▼              ▼                 ▼                ▼
              LocationService   Spot match      ParkinRules       syncProtection()
              (one-shot fix)   (zone memory)   (free/paid math)  (NotificationManager)
                                                            │
                                   confirmPaid / extend ────┤
                                                            ▼
                              LiveActivityManager + WidgetSessionStore
                              (lock screen, Dynamic Island, widgets via
                               App Group group.com.avjoshi.dxbpark)
```

- **`Sources/`** — app target: views (Home, Pass, Spots, Settings, Onboarding), `ParkinRules`, `NotificationManager`, `LiveActivityManager`, `WidgetSessionStore`, SwiftData models (`Session`, `Spot`)
- **`Widgets/`** — widget extension: Live Activity UI + ParkNow widget
- **`Tests/`** — 20 unit tests (rules boundaries + widget session store)
- **`project.yml`** — XcodeGen project definition (targets, entitlements, signing)

**Dev conveniences:** Settings ▸ Developer has a force-paid toggle, demo-session seeder, and test-fire notification buttons; `-demoSession` launch argument seeds a paid session for simulators/screenshots.

## 6. Guardrails (what this app deliberately is *not*)

- **Not a payment processor** — it pre-fills *your* SMS to Parkin; the carrier bills you (~AED 0.30/msg). It never touches money.
- **Not affiliated with Parkin/RTA** — no scraping, no unofficial APIs; an independent helper.
- **Not a tracker** — no background location, no geofencing loops, no server.
- **Never claims "Paid"** without your explicit confirmation.

## 7. Building & running

```bash
cd dxb-park-ios
xcodegen generate                       # project.yml → DXBPark.xcodeproj
open DXBPark.xcodeproj                  # or:
xcodebuild test -scheme DXBPark \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'   # 20 tests

# On-device:
# automatic signing, team YJFN5RLHZH — Product ▸ Run, or archive via
# ExportOptions.plist for TestFlight upload
```
