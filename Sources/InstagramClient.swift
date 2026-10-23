import Foundation
import AppKit
import WebKit

/// The Instagram web app, running for real inside an invisible window.
///
/// The native interface never shows this view. It exists so that every request is made by the
/// genuine web client with the signed-in user's own session, and so the native layer can read
/// what the page receives and drive the page when an action has no direct endpoint.
@MainActor
final class InstagramClient: NSObject, WKNavigationDelegate {
    struct Response {
        let status: Int
        let json: [String: Any]?
    }

    struct NetworkEvent {
        let url: String
        let method: String
        let status: Int
        let body: String
        /// For GraphQL calls: the operation's friendly name and doc id (never the rest of the request body).
        let label: String
    }

    enum ClientError: Error {
        case notReady
        case badEnvelope
    }

    /// How long a request waits for the page to (re)load before giving up.
    private static let readinessTimeout: Duration = .seconds(20)
    /// How long after `didFinish` the boot signal may take before the loaded document is used anyway.
    private static let bootGracePeriod: Duration = .seconds(3)

    /// Fallbacks only: the bridge prefers the values found in the page's own scripts (`__prismgram.config`).
    static let appID = "936619743392459"
    static let asbdID = "129477"
    /// `PRISMGRAM_DEBUG=1` logs each request's path and HTTP status (never bodies) to standard error.
    static let isDebugging = ProcessInfo.processInfo.environment["PRISMGRAM_DEBUG"] != nil
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Safari/605.1.15"
    private static let engineSize = NSSize(width: 1100, height: 900)

    let webView: WKWebView
    var onNetworkEvent: ((NetworkEvent) -> Void)?

    private let hostWindow: NSWindow
    private var isDocumentLoaded = false
    private var isAppBooted = false
    private var bootFallback: Task<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isLeaseHeld = false
    private var leaseQueue: [CheckedContinuation<Void, Never>] = []

    override init() {
        let controller = WKUserContentController()
        controller.addUserScript(
            WKUserScript(source: BridgeScripts.networkTap, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        controller.addUserScript(
            WKUserScript(source: BridgeScripts.bootSignal, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        controller.addUserScript(
            WKUserScript(source: BridgeScripts.bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController = controller
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // The host window is always occluded; without this WebKit throttles timers and eventually
        // suspends the page, which is why tapped queries sometimes arrived late or never.
        configuration.preferences.inactiveSchedulingPolicy = .none

        let frame = NSRect(origin: .zero, size: Self.engineSize)
        let view = WKWebView(frame: frame, configuration: configuration)
        view.customUserAgent = Self.userAgent
        view.isInspectable = true
        webView = view

        // Offscreen host window so WebKit maintains full layout/JS execution without interfering with SwiftUI WindowGroup.
        let offscreenFrame = NSRect(x: -16000, y: -16000, width: Self.engineSize.width, height: Self.engineSize.height)
        let window = NSWindow(contentRect: offscreenFrame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.alphaValue = 0.0
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        window.canHide = false
        window.collectionBehavior = [.transient, .ignoresCycle, .stationary]
        window.contentView = view
        hostWindow = window

        super.init()

        view.navigationDelegate = self
        controller.add(NetworkTapProxy(client: self), name: "igTap")
        controller.add(NetworkTapProxy(client: self), name: "igReady")
    }

    // MARK: Session

    func sessionCookies() async -> [HTTPCookie] {
        await WKWebsiteDataStore.default().httpCookieStore.allCookies().filter { $0.domain.hasSuffix("instagram.com") }
    }

    func viewerID() async -> String? {
        let cookies = await sessionCookies()
        guard cookies.contains(where: { $0.name == "sessionid" && !$0.value.isEmpty }) else { return nil }
        return cookies.first(where: { $0.name == "ds_user_id" })?.value
    }

    func prepare() async {
        hostWindow.orderBack(nil)
        isDocumentLoaded = false
        isAppBooted = false
        if let url = URL(string: "https://www.instagram.com/") {
            webView.load(URLRequest(url: url))
        }
        _ = await waitUntilReady(timeout: Self.readinessTimeout)
    }

    /// The page is usable once its document finished loading and the single-page app has booted.
    private var isReady: Bool { isDocumentLoaded && isAppBooted }

    /// Suspends until the page is ready, or the timeout passes. Returns whether the page is ready.
    private func waitUntilReady(timeout: Duration) async -> Bool {
        if isReady { return true }
        let timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.resumeWaiters()
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        timeoutTask.cancel()
        return isReady
    }

    private func resumeWaiters() {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }

    private func resumeWaitersIfReady() {
        if isReady { resumeWaiters() }
    }

    /// Called by the document-start script once the web app has mounted and its csrftoken cookie exists.
    fileprivate func appDidBoot(path: String, bridgeVersion: Int) {
        guard !isAppBooted else { return }
        isAppBooted = true
        Self.debugLog("page booted at \(path) (page bridge v\(bridgeVersion), app bridge v\(BridgeScripts.version))")
        resumeWaitersIfReady()
        if Self.isDebugging {
            Task { @MainActor [weak self] in
                let sources = await self?.callBridge(
                    "config(appID, asbd).appIDSource + '/' + window.__prismgram.config(appID, asbd).asbdSource",
                    arguments: ["appID": Self.appID, "asbd": Self.asbdID]
                ) as? String
                Self.debugLog("header constants (app id / asbd id) from: \(sources ?? "?")")
            }
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isDocumentLoaded = false
        isAppBooted = false
        bootFallback?.cancel()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isDocumentLoaded = true
        resumeWaitersIfReady()
        guard !isAppBooted else { return }
        // If the boot signal never comes (the markup it looks for changed), don't hold every request
        // until the readiness timeout: treat the loaded document as ready after a short grace period.
        bootFallback?.cancel()
        bootFallback = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.bootGracePeriod)
            guard !Task.isCancelled, let self, self.isDocumentLoaded, !self.isAppBooted else { return }
            Self.debugLog("no boot signal after load; using the loaded document")
            self.isAppBooted = true
            self.resumeWaitersIfReady()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // A failed sub-navigation leaves the previous document usable.
        markUsable(webView.url != nil)
        resumeWaiters()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        markUsable(webView.url != nil && !webView.isLoading)
        resumeWaiters()
        if !isReady { scheduleReload() }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        markUsable(false)
        scheduleReload()
    }

    private func markUsable(_ usable: Bool) {
        isDocumentLoaded = usable
        isAppBooted = usable
    }

    private func scheduleReload() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !self.isReady, !self.webView.isLoading,
                  let url = URL(string: "https://www.instagram.com/") else { return }
            self.webView.load(URLRequest(url: url))
        }
    }

    /// Attempts to read the signed-in viewer's username from the page's navigation bar or embedded scripts.
    func detectViewerUsername() async -> String? {
        await callBridge("detectViewerUsername()") as? String
    }

    // MARK: Requests made as the page

    func request(_ path: String, method: String = "GET", body: String? = nil) async throws -> Response {
        guard await waitUntilReady(timeout: Self.readinessTimeout) else { throw ClientError.notReady }

        let arguments: [String: Any] = [
            "path": path,
            "method": method,
            "body": body ?? NSNull(),
            "appID": Self.appID,
            "asbd": Self.asbdID
        ]
        let call = "request(path, method, body, appID, asbd)"
        let raw: Any?
        do {
            raw = try await callBridgeThrowing(call, arguments: arguments)
        } catch {
            // The page may have been replacing its document mid-call; give it one more chance.
            try? await Task.sleep(for: .milliseconds(600))
            guard await waitUntilReady(timeout: Self.readinessTimeout) else { throw ClientError.notReady }
            raw = try await callBridgeThrowing(call, arguments: arguments)
        }

        if Self.isDebugging {
            let status = ((raw as? String)?.data(using: .utf8)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["status"] ?? "?"
            FileHandle.standardError.write(Data("[prismgram] \(method) \(path) -> \(status)\n".utf8))
        }
        guard let text = raw as? String,
              let envelopeData = text.data(using: .utf8),
              let envelope = try JSONSerialization.jsonObject(with: envelopeData) as? [String: Any],
              let status = envelope["status"] as? Int else {
            throw ClientError.badEnvelope
        }

        var json: [String: Any]?
        if let bodyText = envelope["body"] as? String, let bodyData = bodyText.data(using: .utf8) {
            json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        }
        return Response(status: status, json: json)
    }

    // MARK: Page lease

    /// Runs `body` with exclusive use of the hidden page's location.
    ///
    /// There is one page, so anything that navigates, scrolls or types in it (and then waits for the
    /// page's own queries) must not overlap with another such flow, or one would carry the page away
    /// from under the other. Callers queue in FIFO order. Plain `request(_:)` calls don't depend on
    /// the page's address and must not take the lease. Not reentrant: never nest `withPage` calls.
    func withPage<T>(_ purpose: String, _ body: () async throws -> T) async rethrows -> T {
        let queuedAt = ContinuousClock.now
        await acquireLease()
        let acquiredAt = ContinuousClock.now
        Self.debugLog("lease acquired: \(purpose) (waited \(Self.milliseconds(acquiredAt - queuedAt)) ms)")
        defer {
            Self.debugLog("lease released: \(purpose) (held \(Self.milliseconds(ContinuousClock.now - acquiredAt)) ms)")
            releaseLease()
        }
        return try await body()
    }

    private func acquireLease() async {
        guard isLeaseHeld else {
            isLeaseHeld = true
            return
        }
        await withCheckedContinuation { continuation in
            leaseQueue.append(continuation)
        }
    }

    private func releaseLease() {
        if leaseQueue.isEmpty {
            isLeaseHeld = false
        } else {
            // Ownership passes straight to the next waiter; the lease stays held.
            leaseQueue.removeFirst().resume()
        }
    }

    static func debugLog(_ message: @autoclosure () -> String) {
        guard isDebugging else { return }
        FileHandle.standardError.write(Data("[prismgram] \(message())\n".utf8))
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }

    // MARK: Driving the page

    /// Which API responses the page should forward to `onNetworkEvent` (a JavaScript regular expression source), or nil for none.
    func setNetworkTap(pattern: String?) {
        let literal = pattern.map { "new RegExp(\(Self.jsString($0)))" } ?? "null"
        webView.evaluateJavaScript("window.__igTapPattern = \(literal);") { _, _ in }
    }

    /// Navigates inside the single-page app without a reload, the way a click on a link would.
    @discardableResult
    func navigate(to path: String) async -> String? {
        await callBridge("navigate(path)", arguments: ["path": path]) as? String
    }

    /// Opens a conversation in the hidden page by its address and confirms the page really shows it.
    ///
    /// Tries each candidate id in turn (the web app has used both the thread id and its FBID in URLs)
    /// and returns the id whose page loaded with a composer, or nil. Never clicks list rows by name:
    /// that once matched a different person whose name contained the same text.
    func openDirectThread(ids: [String]) async -> String? {
        var tried = Set<String>()
        for id in ids where !id.isEmpty && tried.insert(id).inserted {
            let path = "/direct/t/\(id)/"
            if await currentPath() != path {
                _ = await navigate(to: path)
            }
            for attempt in 0..<24 {
                try? await Task.sleep(for: .milliseconds(250))
                let state = await callBridge("threadState()") as? String
                guard let data = state?.data(using: .utf8),
                      let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let current = info["path"] as? String else { continue }
                if current.contains(id) {
                    if info["composer"] as? Bool == true { return id }
                } else if attempt > 8 {
                    break // The app redirected away from this id; try the next one.
                }
            }
        }
        return nil
    }

    /// Scrolls the page to its end, which makes instagram.com load the next page of whatever grid it shows.
    func scrollToBottom() async {
        _ = await callBridge("scrollToBottom()")
    }

    func currentPath() async -> String? {
        await callBridge("currentPath()") as? String
    }

    /// Types and sends a message in the hidden page, but only if it is still showing `/direct/t/<threadPathID>/`.
    func sendDirectMessage(text: String, threadPathID: String) async -> Bool {
        let result = await callBridge("sendDirectMessage(text, expected)", arguments: ["text": text, "expected": threadPathID])
        return (result as? Bool) ?? false
    }

    /// Uses the hidden page's own hover controls to react to (`"react"`) or start a reply to (`"reply"`)
    /// the newest message with this text, in the thread the page is verifiably showing.
    func performMessageAction(_ action: String, messageText: String, emoji: String?, threadPathID: String) async -> Bool {
        let result = await callBridge("messageAction(action, text, emoji, expected)", arguments: [
            "action": action, "text": messageText, "emoji": emoji ?? "", "expected": threadPathID
        ])
        return (result as? Bool) ?? false
    }

    /// Calls `window.__prismgram.<call>` in the page, (re)installing the bridge first if the page
    /// replaced its window since the document-start injection. `call` may only refer to `arguments` keys.
    func callBridge(_ call: String, arguments: [String: Any] = [:]) async -> Any? {
        try? await callBridgeThrowing(call, arguments: arguments)
    }

    private func callBridgeThrowing(_ call: String, arguments: [String: Any] = [:]) async throws -> Any? {
        let script = BridgeScripts.bridge + "\nreturn await window.__prismgram.\(call);"
        return try await webView.callAsyncJavaScript(script, arguments: arguments, in: nil, contentWorld: .page)
    }

    fileprivate func receive(url: String, method: String, status: Int, body: String, label: String) {
        onNetworkEvent?(NetworkEvent(url: url, method: method, status: status, body: body, label: label))
    }

    private static func jsString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value), let text = String(data: data, encoding: .utf8) else { return "\"\"" }
        return text
    }
}

final class NetworkTapProxy: NSObject, WKScriptMessageHandler {
    private weak var client: InstagramClient?

    init(client: InstagramClient) {
        self.client = client
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "igReady" {
            let info = message.body as? NSDictionary
            let path = (info?["path"] as? String) ?? "?"
            let version = (info?["bridge"] as? NSNumber)?.intValue ?? 0
            Task { @MainActor [weak client] in
                client?.appDidBoot(path: path, bridgeVersion: version)
            }
            return
        }
        guard message.name == "igTap", let body = message.body as? NSDictionary,
              let url = body["url"] as? String,
              let text = body["body"] as? String else { return }
        let method = (body["method"] as? String) ?? "GET"
        let status = (body["status"] as? NSNumber)?.intValue ?? 0
        let label = (body["label"] as? String) ?? ""
        Task { @MainActor [weak client] in
            client?.receive(url: url, method: method, status: status, body: text, label: label)
        }
    }
}
