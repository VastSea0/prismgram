# Agent instructions

Prismgram is a native macOS SwiftUI client (Swift 6.2, macOS 26) for the user's own Instagram
account. It drives a hidden `WKWebView` running instagram.com (see `Sources/InstagramClient.swift`).

## Ongoing work — read this first

A multi-step refactor is in progress: **[docs/BRIDGE_REFACTOR.md](docs/BRIDGE_REFACTOR.md)**.
If you were asked to "continue", open that file, take the first unchecked task, and follow its
ground rules (build before every commit, small commits, tick the box and append to the
progress log in the same commit).

## Basics

- Build: `swift build` (fast check) · App bundle: `scripts/build-app.sh` then `open Prismgram.app`
- Debug logging: `PRISMGRAM_DEBUG=1`
- User-facing strings are Turkish; code, comments and commit messages are English.
- JS syntax check for the page bridge: `scripts/check-bridge-js.sh` (all page JS lives in `Sources/BridgeScripts.swift`)
