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

        let frame = NSRect(origin: .zero, size: Self.engineSize)
        let view = WKWebView(frame: frame, configuration: configuration)
        view.customUserAgent = Self.userAgent
        view.isInspectable = true
        webView = view

        // A window that is "on screen" keeps WebKit from throttling the page, but nobody can see or touch it.
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.alphaValue = 0.01
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.transient, .ignoresCycle, .stationary]
        window.contentView = view
        hostWindow = window

        super.init()

        view.navigationDelegate = self
        controller.add(NetworkTapProxy(client: self), name: "igTap")
        window.orderBack(nil)
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
        isReady = false
        if let url = URL(string: "https://www.instagram.com/") {
            webView.load(URLRequest(url: url))
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        try? await Task.sleep(for: .seconds(1.5))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isReady = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
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
        guard isReady else { throw ClientError.notReady }

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

        let raw = try await webView.callAsyncJavaScript(
            script,
            arguments: [
                "path": path,
                "method": method,
                "body": body ?? NSNull(),
                "appID": Self.appID
            ],
            in: nil,
            contentWorld: .page
        )

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

    /// Selects a direct message thread in the hidden inbox by matching its title or username, or navigating to `/direct/t/<threadID>/`.
    func openDirectThread(threadID: String, title: String, username: String?) async {
        let script = """
        const nav = document.querySelector('div[role="navigation"]') || document.body;
        const buttons = Array.from(nav.querySelectorAll('div[role="button"], a[role="link"]'));
        const targets = [title, username].filter(Boolean).map(s => s.toLowerCase());
        for (const btn of buttons) {
            const text = (btn.innerText || '').toLowerCase();
            if (targets.some(t => t && text.includes(t))) {
                btn.click();
                return 'clicked';
            }
        }
        return 'not-found';
        """
        let res = (await evaluate(script, arguments: ["title": title, "username": username ?? ""]) as? String) ?? ""
        if res != "clicked" {
            _ = await navigate(to: "/direct/t/\(threadID)/")
        }
    }

    /// Types and sends a direct message in the currently open thread inside the hidden WebView.
    func sendDirectMessage(text: String) async -> Bool {
        let script = """
        const box = document.querySelector('[contenteditable="true"][role="textbox"]')
            || document.querySelector('[contenteditable="true"]')
            || document.querySelector('textarea');
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
        const enterDown = new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true });
        box.dispatchEvent(enterDown);
        await new Promise(r => setTimeout(r, 100));
        const remaining = (box.innerText || box.value || '').trim();
        if (remaining.length > 0) {
            const buttons = Array.from(document.querySelectorAll('div[role="button"], button'));
            const sendBtn = buttons.find(b => {
                const t = (b.innerText || b.getAttribute('aria-label') || '').toLowerCase();
                return t === 'send' || t === 'gönder';
            });
            if (sendBtn) { sendBtn.click(); }
        }
        return true;
        """
        return (await evaluate(script, arguments: ["text": text]) as? Bool) ?? false
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
