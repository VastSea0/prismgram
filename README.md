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

## Architecture

Prismgram renders its entire UI in SwiftUI (`AppStore` + view files) while keeping an offscreen
`WKWebView` running `instagram.com` so every request is issued by the genuine web client with
your signed-in session:

- **`BridgeScripts`** (`Sources/BridgeScripts.swift`) — Installs a versioned `window.__prismgram`
  object at document start (`request`, `navigate`, `scrollToBottom`, `threadState`,
  `sendDirectMessage`, `messageAction`, `detectViewerUsername`, `config`), plus the `igReady`
  SPA boot signal and the `igTap` `fetch`/XHR network tap. Header constants (`X-IG-App-ID`,
  `X-ASBD-ID`) are read from the page's own inline scripts with safe fallbacks, and DOM actions
  use ordered structural/multi-language strategies that return `{ok, step, strategy}` diagnostics.
- **`InstagramClient` & `InstagramTransport`** (`Sources/InstagramClient.swift`) — Owns the
  hidden `WKWebView`, waits for both `didFinish` and `igReady` (with a 3 s grace fallback), and
  serializes any flow that navigates, scrolls or types in the page through `withPage(_:_:)` so
  concurrent profile and DM flows cannot steal the page from one another.
- **`InstagramAPI` & `APIModels`** (`Sources/InstagramAPI.swift`, `Sources/APIModels.swift`) —
  Typed wrappers and `Decodable` response models for every `/api/v1/` endpoint, converting wire
  payloads into the domain models in `Sources/Models.swift` and logging exact `codingPath`s when
  `PRISMGRAM_DEBUG=1` is set.

## Status

See [docs/FEATURES.md](docs/FEATURES.md) for what works and what is still missing.

## License

MIT, see [LICENSE](LICENSE).
