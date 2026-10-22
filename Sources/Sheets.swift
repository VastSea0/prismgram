import SwiftUI
import WebKit
import AppKit

// MARK: - Post detail + comments

struct PostDetailView: View {
    let postID: String
    let fallback: IGPost
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var comments: [IGComment] = []
    @State private var phase: AppStore.Phase = .idle
    @State private var draft = ""
    @State private var isSending = false
    @State private var sendError: String?

    private var post: IGPost { store.livePost(postID) ?? fallback }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    PostView(post: post, store: store, showsCommentLink: false)
                    Divider().opacity(0.6)

                    switch phase {
                    case .idle, .loading:
                        ProgressView().padding(24)
                    case .failed(let message):
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(24)
                    case .loaded:
                        if comments.isEmpty {
                            Text("Henüz yorum yok")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(24)
                        }
                        ForEach(comments) { comment in
                            HStack(alignment: .top, spacing: 10) {
                                Button {
                                    let author = comment.user
                                    dismiss()
                                    store.openProfile(of: author)
                                } label: {
                                    AvatarView(url: comment.user.avatarURL, size: 30)
                                }
                                .buttonStyle(.plain)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("**\(comment.user.username)**  \(comment.text)")
                                        .font(.system(size: 13))
                                    Text(comment.createdAt, format: .relative(presentation: .named))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                    }
                }
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                let canSend = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
                VStack(alignment: .leading, spacing: 4) {
                    if let sendError {
                        Text(sendError).font(.caption).foregroundStyle(.red)
                    }
                    HStack(spacing: 8) {
                        AvatarView(url: store.profile?.avatarURL, size: 26)
                        HStack(spacing: 6) {
                            TextField("Yorum ekle…", text: $draft)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                                .onSubmit(send)
                            Button(action: send) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .symbolRenderingMode(.hierarchical)
                                    .font(.system(size: 22))
                                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                            .disabled(!canSend)
                        }
                        .padding(.leading, 12)
                        .padding(.trailing, 5)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
                        .overlay {
                            Capsule().strokeBorder(.primary.opacity(0.14), lineWidth: 0.8)
                        }
                    }
                }
                .padding(12)
                .background(.bar)
            }
            .navigationTitle(post.user.username)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
        .frame(width: 480, height: 720)
        .task { await loadComments() }
        .onDisappear { store.detailPost = nil }
    }

    private func loadComments() async {
        phase = .loading
        do {
            comments = try await store.loadComments(for: postID)
            phase = .loaded
        } catch {
            phase = .failed((error as? AppStore.RequestFailure)?.message ?? "Yorumlar yüklenemedi.")
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        sendError = nil
        Task {
            do {
                if let comment = try await store.addComment(to: postID, text: text) {
                    withAnimation(.spring(duration: 0.25)) {
                        comments.append(comment)
                    }
                } else {
                    await loadComments()
                }
                draft = ""
            } catch {
                sendError = (error as? AppStore.RequestFailure)?.message ?? "Yorum gönderilemedi."
            }
            isSending = false
        }
    }
}

// MARK: - Sign in (the only place web content is ever shown)

struct LoginSheet: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LoginWebView()
                .navigationTitle("Instagram Hesabıyla Giriş")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Vazgeç") { dismiss() }
                    }
                }
        }
        .frame(width: 440, height: 680)
        .task {
            while !Task.isCancelled {
                if await store.client.viewerID() != nil {
                    await store.didSignIn()
                    return
                }
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }
}

struct LoginWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.customUserAgent = InstagramClient.userAgent
        if let url = URL(string: "https://www.instagram.com/accounts/login/") {
            view.load(URLRequest(url: url))
        }
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - In-app Instagram page (signed-in session)

/// Shows an instagram.com page in a sheet with the app's own session, for things that have no native
/// screen yet (some settings, shared links).
struct WebPageSheet: View {
    let request: AppStore.WebPageRequest
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            InstagramPageView(url: request.url, title: $title, isLoading: $isLoading)
                .overlay(alignment: .top) {
                    if isLoading { ProgressView().controlSize(.small).padding(8) }
                }
                .navigationTitle(request.title ?? (title.isEmpty ? "Instagram" : title))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Kapat") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            NSWorkspace.shared.open(request.url)
                        } label: {
                            Label("Tarayıcıda Aç", systemImage: "safari")
                        }
                    }
                }
        }
        .frame(width: 520, height: 740)
    }
}

struct InstagramPageView: NSViewRepresentable {
    let url: URL
    @Binding var title: String
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.customUserAgent = InstagramClient.userAgent
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: InstagramPageView
        init(_ parent: InstagramPageView) { self.parent = parent }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            parent.title = webView.title?.replacingOccurrences(of: " • Instagram", with: "") ?? ""
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }
    }
}
