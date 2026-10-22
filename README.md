# Prismgram

A native macOS SwiftUI client for your own Instagram account, built with Apple's Liquid Glass
design language and three window layouts (Phone, Hybrid, Desktop).

> **No guarantees & no affiliation.** Prismgram is an independent, open-source hobby project.
> It is not affiliated with, endorsed by, or sponsored by Meta Platforms, Inc. or Instagram.
> It uses an original copyright-free optical aperture icon (`scripts/generate-icon.swift`).
> It can stop working whenever Instagram changes its web application, and using third-party
> clients may conflict with Instagram's terms. It does not bypass anything, unlock private
> content, or modify platform behavior — it only displays and interacts with what your own
> signed-in session already receives. Use it at your own risk.

## Requirements

- macOS 26 or later
- Xcode 26 or later (Swift 6.2 toolchain)

## Build and run

```sh
scripts/build-app.sh
open Prismgram.app
```

On first launch you sign in through Instagram's own login page. After that the session is
kept in the app's persistent website data store.

## Layouts & Shortcuts

- **Phone (`⌃1`)** — Compact iOS-proportioned single-column window (`430×880`) with a floating Liquid Glass tab bar
- **Hybrid (`⌃2`)** — Two-column macOS split view (`1000×860`)
- **Desktop (`⌃3`)** — Full three-column workspace (`1400×920`) with the live Notifications inspector (`⌥⌘I`)

## Status

See [docs/FEATURES.md](docs/FEATURES.md) for what works and what is still missing.

## License

MIT, see [LICENSE](LICENSE).
