# Tension Mirror

A native SwiftUI app (macOS + iOS, one codebase) for browsing, filtering,
and tracking climbs on a [Tension Board 2](https://tensionclimbing.com/)
(Mirror layout, 12×12). It talks directly to a [Turso](https://turso.tech)
database over HTTPS - no server in between - and can light up a climb on
the physical board over Bluetooth.

⚠️ **Single-user by design.** There's no login and no per-user data
separation: whoever's Turso database the app points at, their favorites/
tries/sends are the ones you'll see and change. This was built for one
person's own board. To actually use it yourself, point it at your **own**
Turso database (see below) rather than someone else's.

## What you need

- A Mac with Xcode 15 or newer.
- A free Apple ID (Xcode → Settings → Accounts → **+**) - no paid Apple
  Developer Program required to build and run this yourself, on the
  Simulator, on your Mac, or on your own iPhone.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) - this repo doesn't
  commit an `.xcodeproj`; it's generated from `project.yml`.
  ```
  brew install xcodegen
  ```
- A free [Turso](https://turso.tech) account and its CLI:
  ```
  curl -sSfL https://get.tur.so/install.sh | bash
  turso auth login
  ```
- Your own board data to populate that database with. This repo only
  contains the app - the scripts that sync a real Tension Board's climb
  catalog (via [boardlib](https://github.com/lemeryfertitta/boardlib)) and
  export it into a Turso-ready SQLite file live in the companion
  [tension-mirror](https://github.com/NathanHB/tension-mirror) repo
  (`scripts/export_to_turso.py`). Follow that repo's setup first to get a
  `turso_export.sqlite` file, then:
  ```
  turso db create tension-mirror --from-file turso_export.sqlite --wait
  turso db show tension-mirror --url
  turso db tokens create tension-mirror
  ```

## Setup

1. Clone this repo.
2. Copy the secrets template and fill in the URL/token from the Turso
   commands above:
   ```
   cp Secrets.example.swift.txt Sources/Secrets.swift
   ```
   Edit `Sources/Secrets.swift` with your real `tursoURL` and `tursoToken`.
   This file is gitignored - it never gets committed.
3. Generate the Xcode project:
   ```
   xcodegen generate
   ```
4. Open `TensionMirror.xcodeproj` in Xcode.

## Running it

**On the Simulator or your Mac** (schemes `TensionMirror_iOS` /
`TensionMirror_macOS`): just pick the scheme and destination in Xcode's
toolbar and hit Run (▶). No extra signing setup needed for the Simulator
or a local Mac run.

**On your own iPhone:**

1. Xcode → Settings → Accounts → **+** → sign in with your Apple ID.
2. Select the **TensionMirror_iOS** target → **Signing & Capabilities** →
   pick your personal team under "Team" (leave "Automatically manage
   signing" on).
3. Plug your iPhone in with a cable the first time, and tap **Trust This
   Computer** on the phone if prompted. (After that you can go wireless via
   Xcode → Window → Devices and Simulators → "Connect via network.")
4. Pick your iPhone in Xcode's destination picker and hit Run (▶).
5. First launch will be blocked with "Untrusted Developer" - on the phone,
   go to **Settings → General → VPN & Device Management**, tap the profile
   matching your Apple ID, and tap **Trust**.
6. Launch the app from the home screen.

With a free (non-paid) Apple ID the install expires after 7 days and needs
re-running from Xcode to refresh. A paid Apple Developer Program
membership ($99/year) gives a 1-year certificate and unlocks TestFlight
for cable-free installs, but isn't required just to try it out.

## Bluetooth

Lighting up a climb on the physical board requires the app to have
Bluetooth permission (you'll be prompted on first use) and the board
powered on and in range. The app scans for nearby devices and lets you
pick yours from a list, since Tension boards don't reliably advertise a
recognizable name.
