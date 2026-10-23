import Foundation

/// Every piece of JavaScript that runs inside the hidden instagram.com page.
///
/// Keeping it in one place (instead of string literals spread over `InstagramClient`) makes the
/// page-side contract visible: `bridge` installs `window.__prismgram`, whose methods are the only
/// entry points native code calls. To try a method by hand, open the hidden page in Safari's
/// Web Inspector (the view is inspectable) and call e.g. `await __prismgram.currentPath()`.
enum BridgeScripts {
    /// Bump when the bridge's methods or results change shape.
    static let version = 2

    /// Installs `window.__prismgram` unless it already exists. Injected at document start and
    /// prepended to calls (see `InstagramClient.callBridge`) in case the page replaced its window.
    static let bridge = #"""
    (function() {
        if (window.__prismgram && window.__prismgram.version === __VERSION__) { return; }
        const sleep = (ms) => new Promise(r => setTimeout(r, ms));

        window.__prismgram = {
            version: __VERSION__,
            _config: null,

            /// Header values the web app itself uses, read from its inline scripts. Only explicitly named keys
            /// are accepted (a generic "appId" could be another Meta app's id). Falls back to the values
            /// passed in by native code; a fallback result is re-read after 30 s in case the page was early.
            config(fallbackAppID, fallbackASBD) {
                const cached = this._config;
                if (cached && (cached.source === 'page' || Date.now() - cached.at < 30000)) { return cached; }
                let appID = null, asbd = null;
                try {
                    const scripts = Array.from(document.querySelectorAll('script:not([src])'));
                    for (const s of scripts) {
                        const text = s.textContent || '';
                        if (!appID) {
                            const m = text.match(/"X-IG-App-ID"\s*:\s*"(\d{10,20})"/);
                            if (m) { appID = m[1]; }
                        }
                        if (!asbd) {
                            const m = text.match(/"(?:X-ASBD-ID|ASBD_ID)"\s*:\s*"?(\d{3,10})"?/);
                            if (m) { asbd = m[1]; }
                        }
                        if (appID && asbd) { break; }
                    }
                } catch (_) {}
                const result = {
                    appID: appID || fallbackAppID,
                    asbd: asbd || fallbackASBD,
                    appIDSource: appID ? 'page' : 'fallback',
                    asbdSource: asbd ? 'page' : 'fallback',
                    source: (appID && asbd) ? 'page' : 'fallback',
                    at: Date.now()
                };
                this._config = result;
                return result;
            },

            /// Calls an instagram.com endpoint as the web app would, with the session's own headers.
            async request(path, method, body, appID, asbd) {
                const config = this.config(appID, asbd);
                const csrf = (document.cookie.match(/csrftoken=([^;]+)/) || [])[1] || '';
                const claim = sessionStorage.getItem('www-claim-v2') || '0';
                const headers = {
                    'X-IG-App-ID': config.appID,
                    'X-CSRFToken': csrf,
                    'X-Requested-With': 'XMLHttpRequest',
                    'X-ASBD-ID': config.asbd,
                    'X-IG-WWW-Claim': claim,
                    'X-Instagram-AJAX': '1'
                };
                const options = { method: method, credentials: 'include', headers: headers };
                if (body !== null && body !== undefined) {
                    headers['Content-Type'] = 'application/x-www-form-urlencoded';
                    options.body = body;
                }
                const response = await fetch(path, options);
                return JSON.stringify({ status: response.status, body: await response.text() });
            },

            /// Navigates inside the single-page app without a reload, the way a click on a link would.
            navigate(path) {
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
            },

            /// Scrolls to the end, which makes instagram.com load the next page of the grid it shows.
            scrollToBottom() {
                const main = document.scrollingElement || document.documentElement;
                main.scrollTo(0, main.scrollHeight);
                window.dispatchEvent(new Event('scroll'));
                return true;
            },

            currentPath() {
                return location.pathname;
            },

            /// Where the page is and whether a message composer is on screen.
            threadState() {
                return JSON.stringify({
                    path: location.pathname,
                    composer: !!document.querySelector('[contenteditable="true"][role="textbox"], div[role="main"] textarea')
                });
            },

            /// Reads the signed-in viewer's username from the navigation bar or embedded scripts.
            detectViewerUsername() {
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
            },

            /// Types and sends a message, but only while the page shows `/direct/t/<expected>/`.
            async sendDirectMessage(text, expected) {
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
                await sleep(120);
                if (!location.pathname.includes('/direct/t/' + expected)) { return false; }
                box.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true }));
                await sleep(150);
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
            },

            /// Uses the page's hover controls to react to (`react`) or start a reply to (`reply`) the newest
            /// message with this text, in the thread the page verifiably shows.
            async messageAction(action, text, emoji, expected) {
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
            }
        };
    })();
    """#.replacingOccurrences(of: "__VERSION__", with: String(version))

    /// Posts `igReady` once the web app has mounted and its csrftoken cookie exists.
    static let bootSignal = #"""
    (function() {
        if (window.__igBootWatch) { return; }
        window.__igBootWatch = true;
        var tries = 0;
        function booted() {
            if (!/(?:^|;\s*)csrftoken=/.test(document.cookie)) { return false; }
            var root = document.querySelector('[id^="mount_"]');
            if (root && root.childElementCount > 0) { return true; }
            return !!document.querySelector('main, nav, [role="main"]');
        }
        function check() {
            if (booted()) {
                try { window.webkit.messageHandlers.igReady.postMessage({ path: location.pathname, bridge: (window.__prismgram && window.__prismgram.version) || 0 }); } catch (_) {}
                return;
            }
            if (++tries < 200) { setTimeout(check, 100); }
        }
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', check);
        } else {
            check();
        }
    })();
    """#

    /// Wraps `fetch` and XHR so responses whose URL matches `window.__igTapPattern` are forwarded
    /// to the `igTap` handler, labelled with the GraphQL operation's friendly name and doc id.
    static let networkTap = #"""
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
