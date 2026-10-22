import Foundation
import WebKit

/// Invisible same-origin transport. The WKWebView below is never added to any window;
/// it only exists so requests carry the user's own instagram.com session exactly like the site does.
@MainActor
final class InstagramClient: NSObject, WKNavigationDelegate {
    struct Response {
        let status: Int
        let json: [String: Any]?
    }

    enum ClientError: Error {
        case notReady
        case badEnvelope
    }

    static let appID = "936619743392459"
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Safari/605.1.15"

    let webView: WKWebView
    private var isReady = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: configuration)
        webView.customUserAgent = Self.userAgent
        super.init()
        webView.navigationDelegate = self
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

    // MARK: Requests

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
}
