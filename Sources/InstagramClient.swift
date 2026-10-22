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

    static let appID = "936619743392459"
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Safari/605.1.15"
    private static let engineSize = NSSize(width: 1100, height: 900)

    let webView: WKWebView
    var onNetworkEvent: ((NetworkEvent) -> Void)?

    private let hostWindow: NSWindow
    private var isReady = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    override init() {
        let controller = WKUserContentController()
        controller.addUserScript(
            WKUserScript(source: Self.networkTapScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
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
        isReady = false
        if let url = URL(string: "https://www.instagram.com/") {
            webView.load(URLRequest(url: url))
        }
        _ = await waitUntilReady(timeout: Self.readinessTimeout)
        try? await Task.sleep(for: .seconds(1.5))
    }

    /// Suspends until the page has finished loading, or the timeout passes. Returns whether the page is ready.
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

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isReady = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isReady = true
        resumeWaiters()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // A failed sub-navigation leaves the previous document usable.
        isReady = webView.url != nil
        resumeWaiters()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isReady = webView.url != nil && !webView.isLoading
        resumeWaiters()
        if !isReady { scheduleReload() }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isReady = false
        scheduleReload()
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
        let script = """
        const reserved = new Set(['explore', 'reels', 'direct', 'accounts', 'stories', 'p', 'tv', 'reel', 'challenge', 'legal', 'about', 'developer']);
        const links = Array.from(document.querySelectorAll('a[href]'));
        for (const a of links) {
            const href = a.getAttribute('href') || '';
            const parts = href.split('/').filter(Boolean);
            if (parts.length === 1 && !reserved.has(parts[0]) && /^[A-Za-z0-9._]{1,30}$/.test(parts[0])) {
                if (a.querySelector('img, svg, span')) {
                    return parts[0];
                }
            }
        }
        const html = document.documentElement.innerHTML;
        const m = html.match(/"username":"([A-Za-z0-9._]{1,30})"/);
        return m ? m[1] : null;
        """
        return await evaluate(script) as? String
    }

    // MARK: Requests made as the page

    func request(_ path: String, method: String = "GET", body: String? = nil) async throws -> Response {
        guard await waitUntilReady(timeout: Self.readinessTimeout) else { throw ClientError.notReady }

        let script = """
        const csrf = (document.cookie.match(/csrftoken=([^;]+)/) || [])[1] || '';
        const claim = sessionStorage.getItem('www-claim-v2') || '0';
        const headers = {
            'X-IG-App-ID': appID,
            'X-CSRFToken': csrf,
            'X-Requested-With': 'XMLHttpRequest',
            'X-ASBD-ID': '129477',
            'X-IG-WWW-Claim': claim,
            'X-Instagram-AJAX': '1'
        };
        const options = { method: method, credentials: 'include', headers: headers };
        if (body !== null) {
            headers['Content-Type'] = 'application/x-www-form-urlencoded';
            options.body = body;
        }
        const response = await fetch(path, options);
        return JSON.stringify({ status: response.status, body: await response.text() });
        """

        let arguments: [String: Any] = [
            "path": path,
            "method": method,
            "body": body ?? NSNull(),
            "appID": Self.appID
        ]
        let raw: Any?
        do {
            raw = try await webView.callAsyncJavaScript(script, arguments: arguments, in: nil, contentWorld: .page)
        } catch {
            // The page may have been replacing its document mid-call; give it one more chance.
            try? await Task.sleep(for: .milliseconds(600))
            guard await waitUntilReady(timeout: Self.readinessTimeout) else { throw ClientError.notReady }
            raw = try await webView.callAsyncJavaScript(script, arguments: arguments, in: nil, contentWorld: .page)
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

    // MARK: Driving the page

    /// Which API responses the page should forward to `onNetworkEvent` (a JavaScript regular expression source), or nil for none.
    func setNetworkTap(pattern: String?) {
        let literal = pattern.map { "new RegExp(\(Self.jsString($0)))" } ?? "null"
        webView.evaluateJavaScript("window.__igTapPattern = \(literal);") { _, _ in }
    }

    /// Navigates inside the single-page app without a reload, the way a click on a link would.
    @discardableResult
    func navigate(to path: String) async -> String? {
        let script = """
        const exact = document.querySelector('a[href="' + path + '"]');
        if (exact) { exact.click(); return 'click'; }
        const temp = document.createElement('a');
        temp.href = path;
        temp.style.display = 'none';
        document.body.appendChild(temp);
        temp.click();
        temp.remove();
        if (window.location.pathname === path) { return 'anchor'; }
        window.history.pushState({}, '', path);
        window.dispatchEvent(new PopStateEvent('popstate', { state: {} }));
        return 'push';
        """
        let result = try? await webView.callAsyncJavaScript(script, arguments: ["path": path], in: nil, contentWorld: .page)
        return result as? String
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
                let state = await evaluate("""
                return JSON.stringify({
                    path: location.pathname,
                    composer: !!document.querySelector('[contenteditable="true"][role="textbox"], div[role="main"] textarea')
                });
                """) as? String
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

    func currentPath() async -> String? {
        await evaluate("return location.pathname;") as? String
    }

    /// Types and sends a message in the hidden page, but only if it is still showing `/direct/t/<threadPathID>/`.
    func sendDirectMessage(text: String, threadPathID: String) async -> Bool {
        let script = """
        if (!location.pathname.includes('/direct/t/' + expected)) { return false; }
        const box = document.querySelector('[contenteditable="true"][role="textbox"]')
            || document.querySelector('div[role="main"] textarea');
        if (!box) { return false; }
        box.focus();
        if (box.tagName === 'TEXTAREA' || box.tagName === 'INPUT') {
            const setter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value')?.set;
            if (setter) { setter.call(box, text); } else { box.value = text; }
            box.dispatchEvent(new Event('input', { bubbles: true }));
        } else {
            document.execCommand('selectAll', false, null);
            document.execCommand('insertText', false, text);
            box.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: text }));
        }
        await new Promise(r => setTimeout(r, 120));
        if (!location.pathname.includes('/direct/t/' + expected)) { return false; }
        box.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true }));
        await new Promise(r => setTimeout(r, 150));
        const remaining = (box.innerText || box.value || '').trim();
        if (remaining.length > 0) {
            const send = Array.from(document.querySelectorAll('div[role="button"], button')).find(b => {
                const t = (b.innerText || b.getAttribute('aria-label') || '').trim().toLowerCase();
                return t === 'send' || t === 'gönder';
            });
            if (!send) { return false; }
            send.click();
        }
        return true;
        """
        return (await evaluate(script, arguments: ["text": text, "expected": threadPathID]) as? Bool) ?? false
    }

    /// Uses the hidden page's own hover controls to react to (`"react"`) or start a reply to (`"reply"`)
    /// the newest message with this text, in the thread the page is verifiably showing.
    func performMessageAction(_ action: String, messageText: String, emoji: String?, threadPathID: String) async -> Bool {
        let script = """
        const sleep = (ms) => new Promise(r => setTimeout(r, ms));
        if (!location.pathname.includes('/direct/t/' + expected)) { return false; }
        const main = document.querySelector('div[role="main"]') || document.body;
        const exact = Array.from(main.querySelectorAll('div[dir="auto"], span[dir="auto"], div, span'))
            .filter(e => (e.innerText || '').trim() === text);
        const target = exact[exact.length - 1];
        if (!target) { return false; }
        const row = target.closest('div[role="row"], div[role="gridcell"]') || target.parentElement;
        const fire = (el, type) => el.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, view: window }));
        for (let el = target, i = 0; el && i < 8; el = el.parentElement, i++) {
            ['pointerover', 'mouseover', 'pointerenter', 'mouseenter', 'pointermove', 'mousemove'].forEach(t => fire(el, t));
        }
        await sleep(400);
        const pattern = action === 'react' ? /react|tepki|ifade/i : /reply|yanıt/i;
        const scope = (row && row.querySelectorAll('[aria-label]').length) ? row : main;
        const labelled = Array.from(scope.querySelectorAll('[aria-label]'))
            .filter(e => pattern.test(e.getAttribute('aria-label') || ''));
        const button = labelled.map(e => e.closest('[role="button"], button') || e).pop();
        if (!button) { return false; }
        button.click();
        if (action !== 'react') { return true; }
        await sleep(500);
        const options = Array.from(document.querySelectorAll('[role="button"], button, [role="menuitem"], [role="option"]'));
        const option = options.find(e => {
            const label = (e.innerText || e.getAttribute('aria-label') || (e.querySelector('img') || {}).alt || '').trim();
            return label.startsWith(emoji);
        });
        if (!option) { document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })); return false; }
        option.click();
        return true;
        """
        let result = await evaluate(script, arguments: [
            "action": action, "text": messageText, "emoji": emoji ?? "", "expected": threadPathID
        ])
        return (result as? Bool) ?? false
    }

    func evaluate(_ script: String, arguments: [String: Any] = [:]) async -> Any? {
        try? await webView.callAsyncJavaScript(script, arguments: arguments, in: nil, contentWorld: .page)
    }

    fileprivate func receive(url: String, method: String, status: Int, body: String, label: String) {
        onNetworkEvent?(NetworkEvent(url: url, method: method, status: status, body: body, label: label))
    }

    private static func jsString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value), let text = String(data: data, encoding: .utf8) else { return "\"\"" }
        return text
    }

    private static let networkTapScript = #"""
    (function() {
        if (window.__igTapInstalled) { return; }
        window.__igTapInstalled = true;
        window.__igTapPattern = new RegExp('/api/|/graphql');

        function forward(url, method, status, body, label) {
            try {
                window.webkit.messageHandlers.igTap.postMessage({ url: url, method: method, status: status, body: body, label: label || '' });
            } catch (_) {}
        }
        function labelFor(requestBody) {
            try {
                const text = requestBody instanceof URLSearchParams ? requestBody.toString() : (typeof requestBody === 'string' ? requestBody : '');
                const params = new URLSearchParams(text);
                const name = params.get('fb_api_req_friendly_name') || '';
                const doc = params.get('doc_id') || '';
                return name || doc ? name + ' #' + doc : '';
            } catch (_) { return ''; }
        }
        function wanted(url) {
            return window.__igTapPattern && window.__igTapPattern.test(url);
        }

        const originalFetch = window.fetch;
        window.fetch = async function(input, init) {
            const response = await originalFetch.apply(this, arguments);
            try {
                const url = typeof input === 'string' ? input : (input && input.url) || '';
                if (wanted(url)) {
                    const method = (init && init.method) || (input && input.method) || 'GET';
                    const label = labelFor(init && init.body);
                    response.clone().text().then(function(text) { forward(url, method, response.status, text, label); });
                }
            } catch (_) {}
            return response;
        };

        const originalOpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function(method, url) {
            this.__igURL = String(url);
            this.__igMethod = method;
            return originalOpen.apply(this, arguments);
        };
        const originalSend = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.send = function(requestBody) {
            this.__igLabel = labelFor(requestBody);
            this.addEventListener('load', function() {
                try {
                    if (wanted(this.__igURL) && (this.responseType === '' || this.responseType === 'text')) {
                        forward(this.__igURL, this.__igMethod, this.status, this.responseText, this.__igLabel);
                    }
                } catch (_) {}
            });
            return originalSend.apply(this, arguments);
        };
    })();
    """#
}

final class NetworkTapProxy: NSObject, WKScriptMessageHandler {
    private weak var client: InstagramClient?

    init(client: InstagramClient) {
        self.client = client
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
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
