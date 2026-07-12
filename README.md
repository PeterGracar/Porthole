# Porthole

A native SwiftUI GUI for [MacPorts](https://www.macports.org).

- Browse installed ports (with versions, variants, active state) and uninstall them
- Search the ports tree and install by name
- One-click Selfupdate, Upgrade Outdated, and Reclaim
- Cleanup helpers for inactive versions and leaves, with a preview of what gets removed
- Detail pane with description, homepage, variants, and dependencies
- Live console streaming `port`'s output, with Cancel

## How it works

Root authentication is needed **once**: mutating operations run through a
privileged helper daemon (`PortholeHelper`) registered with `SMAppService`.
You approve it a single time in System Settings; after that, launchd runs it
on demand as root and the app talks to it over XPC. Read-only queries
(listing, search, info) run directly as your user and work without the helper.

The helper only executes a fixed allowlist of `port` subcommands and validates
the connecting app's code signature — it accepts XPC connections only from an
app with the bundle identifier `io.github.petergracar.Porthole` signed by the **same
Apple Development team as the helper itself** (the team is read from the
helper's own signature at runtime, so nothing needs to be edited in code when
you build with your own team).

## Requirements

- macOS 15 (Sequoia) or later
- Xcode 16 or later
- [MacPorts](https://www.macports.org/install.php) installed (`port` on your `PATH`)
- An Apple ID added to Xcode — a **free** account is enough; no paid
  Developer Program membership is required to build and run this on your own
  machine

## Deploying from source

### 1. Clone

```sh
git clone https://github.com/PeterGracar/Porthole.git
cd Porthole
```

### 2. Set up signing (one-time)

Both targets (app and helper) **must be signed with the same team** — the
helper rejects XPC connections from any other signature, and `SMAppService`
requires a valid signature to register the daemon at all. Ad-hoc/unsigned
builds will not work.

1. Xcode → **Settings… → Accounts** → **+** → add your Apple ID. This creates
   a free *Personal Team* and an Apple Development certificate automatically.
2. Find your team ID: select the **Porthole** target → *Signing &
   Capabilities* → pick your team in the **Team** dropdown, then do the same
   for the **PortholeHelper** target. Xcode fills in the 10-character team ID.

   Or edit it directly — the repo has `DEVELOPMENT_TEAM = Y343K25JG3` (my
   personal team) in `Porthole.xcodeproj/project.pbxproj`; replace both
   occurrences with your own team ID. You can read your team ID from any
   cert in your keychain:

   ```sh
   security find-identity -v -p codesigning
   # "Apple Development: you@example.com (ABCDE12345)" — OU in the cert is the team ID
   ```

Signing style is *Automatic*, so no provisioning profiles or entitlements
need to be managed by hand.

### 3. Build

**Xcode:** open `Porthole.xcodeproj`, select the *Porthole* scheme, ⌘B.

**Terminal:**

```sh
xcodebuild -project Porthole.xcodeproj -scheme Porthole -configuration Release build
```

To override the team without touching the project file:

```sh
xcodebuild -project Porthole.xcodeproj -scheme Porthole -configuration Release \
  DEVELOPMENT_TEAM=ABCDE12345 -allowProvisioningUpdates build
```

The helper target builds automatically as a dependency, and the launchd plist
(`SupportFiles/io.github.petergracar.Porthole.helper.plist`) is copied into
`Porthole.app/Contents/Library/LaunchDaemons/` by a build phase.

### 4. Install to /Applications (required)

launchd resolves the helper relative to the *registered* app location, so the
app must run from a stable path — not from DerivedData:

```sh
ditto ~/Library/Developer/Xcode/DerivedData/Porthole-*/Build/Products/Release/Porthole.app /Applications/Porthole.app
open /Applications/Porthole.app
```

(For Debug builds, substitute `Debug` in both the build command and the path.)

### 5. First launch — approve the helper

1. Click **Enable Helper** in the in-app banner.
2. Approve **Porthole** under System Settings → **General → Login Items &
   Extensions** (one admin authentication).
3. The banner disappears; mutating operations (install, upgrade, uninstall…)
   now work.

Rebuilds keep the approval as long as the signing identity, team, and bundle
ID stay the same — just `ditto` the new build over `/Applications/Porthole.app`
and relaunch. When the XPC protocol changes, bump `kHelperVersion` in
`Shared/HelperProtocol.swift`; the app detects the mismatch and re-registers
the daemon automatically, without a new approval prompt.

## Distributing builds to other people (optional)

A free-account build runs fine on your own Mac, but Gatekeeper will block it
on other machines. To hand the app to someone else you need a paid Apple
Developer Program membership and a **Developer ID Application** certificate:

```sh
# Build signed with Developer ID
xcodebuild -project Porthole.xcodeproj -scheme Porthole -configuration Release \
  CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM=ABCDE12345 \
  -allowProvisioningUpdates build

# Zip and notarize
ditto -c -k --keepParent Porthole.app Porthole.zip
xcrun notarytool submit Porthole.zip --keychain-profile "AC_PROFILE" --wait
xcrun stapler staple Porthole.app
```

(`AC_PROFILE` is a keychain profile created once with
`xcrun notarytool store-credentials`.) Everything else — helper validation,
`SMAppService` approval — works the same, because the helper derives the team
from its own signature.

## Tests

Parser unit tests (fixtures captured from MacPorts 2.12.5):

```sh
xcodebuild test -project Porthole.xcodeproj -scheme Porthole -destination 'platform=macOS'
```

## Troubleshooting the helper

- Inspect the daemon: `sudo launchctl print system/io.github.petergracar.Porthole.helper`
- Helper logs: `log show --last 10m --predicate 'process == "PortholeHelper"'`
- Stuck state (approved but old binary answering, duplicate Login Items
  entries): quit the app, delete and re-copy `/Applications/Porthole.app`,
  relaunch, and use **Enable Helper** again.
- Nuclear option: `sfltool resetbtm` resets background-item approvals for
  **all** apps on the machine (every app will re-prompt). Last resort only.

## Project layout

- `Porthole/` — SwiftUI app (read-only `port` queries run here, as your user)
- `PortholeHelper/` — root helper daemon (fixed allowlist of `port` commands,
  validates the connecting app's code signature, streams output over XPC)
- `Shared/` — XPC protocol, models, and output parsers (compiled into app,
  helper, and tests)
- `SupportFiles/io.github.petergracar.Porthole.helper.plist` — launchd daemon plist,
  copied to `Contents/Library/LaunchDaemons/` at build time
- `Scripts/` — CoreGraphics scripts that generate the app icon art
  (`make_icon.swift` for the legacy appiconset, `make_foreground.swift` for
  the macOS 26 Icon Composer `.icon` package)

### Note on renaming (forks)

Changing the *team* requires no code edits. Changing the *bundle identifiers*
does: the identifier `io.github.petergracar.Porthole` is hardcoded in the helper's
code-signing requirement (`PortholeHelper/HelperService.swift`), in the
launchd plist (`SupportFiles/io.github.petergracar.Porthole.helper.plist` — label, Mach
service name, and associated bundle ID), in `Shared/HelperProtocol.swift`
(Mach service name), and in the target build settings. Keep them in sync or
the helper will reject the app.

## License

[MIT](LICENSE)
