# Contributing

This is a personal hobby project, shared in the hope it is useful. Feedback is
genuinely welcome and the project is early, so you will find rough edges.

I may be slow to respond, but every report is read.

## Reporting a bug

[Open an issue](../../issues/new/choose) and use the bug report form. The two most
useful things:

- **A screenshot** if the problem is visual.
- **The sync log line** if a metric fails to load (in the app: *More → Sync log*).
  The Google Health API is new (v4) and some data-type names are not final yet, so a
  single error line is often enough to pin down the fix.

Worth knowing before reporting "no data": values derived from sleep (HRV, respiration,
SpO₂, skin temperature) only appear after you have actually slept wearing the band, and
scores like Fittr Age need roughly 30 days of history before they leave the calibrating
state.

## Pull requests

Before opening one, run the self-tests:

```bash
cd SelfTest && swift run fittr-selftest
```

They cover the whole metric core (PKCE, DTO decoding against Google Health fixtures,
every metric engine end-to-end on demo data, store roundtrip) and run without Xcode, so
they catch most regressions quickly. CI runs the same command on every push.

A few ground rules:

- **Changes to metric logic need a matching check in `SelfTest`.** A score that changes
  silently is worse than no score.
- **Keep it local and private.** No analytics, telemetry, accounts or server component,
  by design. Everything stays in `Application Support` on the phone.
- **Core stays platform-neutral.** `Core/` must not import UIKit or SwiftUI, otherwise
  the self-tests stop working on macOS.
- New metrics should reference published research, the way the existing ones do
  (see [`SETUP.md`](SETUP.md)).

By contributing you agree that your changes are licensed under Apache-2.0.

## Setting up

Build instructions, the Google Cloud setup and the full methodology live in
[`SETUP.md`](SETUP.md). No Fitbit at hand? Demo mode generates 120 days of realistic
sample data, which is enough to work on almost any part of the UI.
