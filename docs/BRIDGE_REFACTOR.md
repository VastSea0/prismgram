# Bridge refactor — handoff plan

This file is the single source of truth for the ongoing refactor of the hidden-WebView bridge.
**Any agent (or human) can pick this up at any point.** Read it top to bottom, find the first
unchecked task, do it, tick it, append to the progress log, commit. Repeat.

## Goal

Keep the hidden `WKWebView` (it is what makes every request come from the genuine web client
with the user's own session) but make the layer between it and SwiftUI smaller, safer and
easier to keep compatible when instagram.com changes. **No user-visible behavior change** unless
a task says so.

## How the bridge works today (read before touching anything)

`Sources/InstagramClient.swift` owns an offscreen, transparent `NSWindow` with a real
`WKWebView` on instagram.com. Native code talks to it in three ways:

1. **Requests made as the page** — `request(_:method:body:)` runs `fetch` inside the page via
   `callAsyncJavaScript`, so cookies, `csrftoken` and `www-claim` come from the page. Used by
   `AppStore.fetch` for feed, explore, likes, comments, follows… (REST `/api/v1/...`).
2. **Network tap** — `networkTapScript` wraps `fetch`/XHR at document start and forwards
   matching responses (with the GraphQL `fb_api_req_friendly_name`) through the `igTap`
   message handler to `AppStore.handleNetworkEvent`. Inbox, DM threads, notes and profiles are
   read this way.
3. **Driving the page** — `navigate(to:)`, `scrollToBottom()`, `openDirectThread`,
   `sendDirectMessage`, `performMessageAction` click/type in the DOM. Fragile: CSS selectors and
   language-dependent strings (`'send'`, `'gönder'`, `/react|tepki|ifade/`).

Known problems this plan fixes:
- The single page is shared state: profile loading (`navigate("/<user>/")`, scrolling) and DMs
  (`openDirectThread`) can navigate it concurrently and break each other.
- Readiness = `didFinish` + a blind `sleep(1.5)`; an SPA is not ready at `didFinish`.
- JS lives in Swift string literals scattered across methods; hard to test in Web Inspector.
- `X-ASBD-ID` and the app ID are hard-coded.
- `AppStore` builds raw API paths itself; there is no seam to swap a transport.
- Parsing is `[String: Any]` everywhere; schema drift fails silently.

## Ground rules

- **Build must pass before every commit:** `swift build 2>&1 | tail -20`, and when you touch
  JavaScript, `scripts/check-bridge-js.sh`. Never commit a broken build. (Release app: `scripts/build-app.sh`, not required per commit.)
- **Small commits, one task (or sub-step) per commit.** In the same commit: tick the checkbox
  below and add a line to the progress log. If you stop mid-task, commit what builds and write
  precisely what is left in the log ("NEXT: ...").
- Commit messages: imperative English subject (≤ 72 chars), a body explaining *why*, matching
  the existing history style (`git log -5`). Do not push; do not rewrite history.
- Keep user-facing strings (Turkish error messages etc.) unchanged.
- Keep existing comments/docstrings that are unrelated to your change.
- No new third-party dependencies. Do not add SPM resources (the app bundle is assembled by
  `scripts/build-app.sh` which does not copy resource bundles) — keep JS in Swift files.
- Do not add anything that bypasses Instagram limits or accesses others' private data. The
  app only shows what the signed-in session already receives (see README).
- You cannot log in from an agent session. Verify by building and by careful reading; list
  anything that needs a manual run in the log under "Manual check".

## Tasks

Do them in order; each depends on the previous ones.

### T1 — Serialize use of the hidden page
- [x] Add a `PageLease`-style serializer in `InstagramClient` (FIFO async mutex on the main
      actor): `func withPage<T>(_ purpose: String, _ body: () async throws -> T) async rethrows -> T`.
- [x] Route every flow that navigates/scrolls/types through it in `AppStore`: story open
      (`navigate("/stories/...")`), direct inbox (`navigate("/direct/inbox/")`), open thread +
      send, react, reply, profile loading (`navigate("/<user>/")`, section paths, `scrollToBottom`).
      Plain `request()` calls must NOT take the lease (they don't depend on the page URL).
- [x] `PRISMGRAM_DEBUG` logs lease acquire/release with the purpose and wait time.

### T2 — Real readiness signal
- [x] Add a document-start script that posts an `igReady` message once the SPA has booted
      (csrftoken cookie present and app root mounted, polled briefly); handle it in Swift.
      (Route-change signals were dropped: SPA navigations never reset readiness, and the
      lease-holding flows already poll for the data they wait for.)
- [x] `waitUntilReady` uses `didFinish` **and** `igReady`; remove the blind `sleep(1.5)` in
      `prepare()` (keep a short fallback timeout so nothing hangs).

### T3 — One JS bridge object
- [x] Create `Sources/BridgeScripts.swift` holding all JS as static strings. Install at
      document start a `window.__prismgram` object with `request`, `navigate`, `scrollToBottom`,
      `currentPath`, `threadState`, `sendDirectMessage`, `messageAction`, `detectViewerUsername`.
- [x] Make `InstagramClient` methods thin calls like
      `callAsyncJavaScript("return await window.__prismgram.request(path, method, body)")`.
      Re-install the object if missing (page replaced) before calling.
- [x] Add `window.__prismgram.version` and log it in debug mode.

### T4 — Read constants from the page
- [x] In the bridge, resolve `X-IG-App-ID` and `X-ASBD-ID` from the page (config/scripts,
      e.g. regex over inline scripts for `"APP_ID":"..."` / `asbd_id`), cache them, fall back to
      the current hard-coded values. Debug-log which source was used.

### T5 — Language-independent, diagnosable DOM automation
- [ ] Replace text matches (`'send'`, `'gönder'`, Turkish/English regexes) with structural
      selectors first, aria-label lists for several languages second, as ordered strategies.
- [ ] Each DOM action returns a structured result `{ok, step, strategy}` instead of a bool;
      Swift logs failures (step name, never message text) in debug mode.

### T6 — Transport seam + typed API
- [ ] Add `protocol InstagramTransport` (`request`, `withPage`, `navigate`, network events)
      implemented by `InstagramClient`.
- [ ] Add `Sources/InstagramAPI.swift`: typed methods for every REST path used in `AppStore`
      (timeline, reelsTray, reelsMedia, exploreGrid, clipsDiscover, topSearch, newsInbox,
      broadcast, logout, setPrivacy, createNote, deleteNote, currentUser, friendship,
      friendshipList, comments, like, save, addComment). `AppStore` calls these; no raw
      `/api/v1` strings left in `AppStore`. One commit per group is fine.

### T7 — Codable models, endpoint by endpoint
- [ ] Introduce `Decodable` response types for the REST endpoints, one endpoint per commit,
      keeping the domain models in `Models.swift`. On decode failure, debug-log the endpoint
      and the coding path (not the payload). Start with timeline, then comments, explore,
      reels, search, activity.

### T8 — Docs
- [ ] Add an "Architecture" section to README describing the final bridge, and update
      `docs/FEATURES.md` notes where the mechanism changed. Mark this plan as done.

## Progress log

Append newest at the bottom: `YYYY-MM-DD HH:MM — <agent> — <task> — <what was done>. NEXT: ...`

- 2026-10-23 11:05 — Antigravity — setup — Plan written; baseline `swift build` passes. NEXT: T1.
- 2026-10-23 11:06 — Antigravity — T1 — `InstagramClient.withPage` (FIFO, non-reentrant) wraps story fallback, inbox, open/send/react/reply, profile open and section/scroll loads; stale profile tokens are rechecked after acquiring. Manual check: open a profile while a DM is sending; both should complete. NEXT: T2.
- 2026-10-23 11:07 — Antigravity — T2 — Readiness = `didFinish` && `igReady` (`bootSignalScript`), with a 3 s grace fallback after `didFinish` so a changed markup never stalls requests; removed the blind 1.5 s sleep. Manual check: `PRISMGRAM_DEBUG=1` should print `page booted at /` on launch. NEXT: T3.
- 2026-10-23 11:09 — Antigravity — T3 — All page JS moved to `BridgeScripts.swift` (`bridge`, `bootSignal`, `networkTap`); `InstagramClient` calls `window.__prismgram.*` via `callBridge`, which prepends the idempotent installer. Added `scripts/check-bridge-js.sh`. Page-reported bridge version is logged on boot. Manual check: in Web Inspector `await __prismgram.currentPath()` works. NEXT: T4.
- 2026-10-23 11:10 — Antigravity — T4 — `__prismgram.config()` reads `"X-IG-App-ID"` / `"X-ASBD-ID"|"ASBD_ID"` from inline scripts (explicit keys only), caches per document, re-reads fallbacks after 30 s; Swift passes `appID`/`asbdID` as fallbacks and debug-logs the source after boot. Bridge v2. Manual check: `PRISMGRAM_DEBUG=1` prints `header constants ... from: page/...`; if it says fallback, nothing changes vs. before. NEXT: T5.
