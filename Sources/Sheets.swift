import SwiftUI
import WebKit
import AppKit

// MARK: - Story viewer

struct StoryViewer: View {
    let tray: IGStoryTray
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    private var activeTray: IGStoryTray {
        if let latest = store.storyViewer, latest.id == tray.id {
            return latest
        }
        return tray
    }

    private var slide: IGMediaItem? { activeTray.slides[safe: index] }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black

            if let slide {
                Group {
                    if let video = slide.videoURL {
                        InlineVideo(url: video, autoplay: true, muted: false, showsControls: false, fillsFrame: false)
                            .allowsHitTesting(false)
                    } else {
                        RemoteImage(url: slide.imageURL)
                    }
                }
                .id(slide.id)
            } else if store.isLoadingStorySlides {
                ProgressView()
                    .tint(.white)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Hikaye yüklenemedi", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: 0) {
                Color.clear.contentShape(.rect).onTapGesture { step(-1) }
                Color.clear.contentShape(.rect).onTapGesture { step(1) }
            }

            VStack(spacing: 10) {
                if !activeTray.slides.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(activeTray.slides.indices, id: \.self) { position in
                            Capsule()
                                .fill(position <= index ? Color.white : Color.white.opacity(0.35))
                                .frame(height: 3)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        let user = activeTray.user
                        dismiss()
                        store.openProfile(of: user)
                    } label: {
                        HStack(spacing: 10) {
                            AvatarView(url: activeTray.user.avatarURL, size: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(activeTray.title ?? activeTray.user.username)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                if activeTray.title != nil {
                                    Text("@\(activeTray.user.username)")
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.75))
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(14)
            .background(
                LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
            )
        }
        .frame(width: 400, height: 710)
        .task(id: "\(activeTray.slides.count)-\(index)") {
            guard !activeTray.slides.isEmpty else { return }
            try? await Task.sleep(for: .seconds(slide?.videoURL == nil ? 6 : 12))
            if !Task.isCancelled { step(1) }
        }
        .onDisappear { store.storyViewer = nil }
    }

    private func step(_ delta: Int) {
        guard !activeTray.slides.isEmpty else { return }
        let next = index + delta
        if next < 0 {
            return
        } else if next >= activeTray.slides.count {
            dismiss()
        } else {
            index = next
        }
    }
}

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
                    Divider()

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
                            Text("Henüz yorum yok").font(.footnote).foregroundStyle(.secondary).padding(24)
                        }
                        ForEach(comments) { comment in
                            HStack(alignment: .top, spacing: 10) {
                                AvatarView(url: comment.user.avatarURL, size: 30)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("**\(comment.user.username)**  \(comment.text)")
                                        .font(.subheadline)
                                    Text(comment.createdAt, format: .relative(presentation: .named))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                    }
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    if let sendError {
                        Text(sendError).font(.caption).foregroundStyle(.red)
                    }
                    HStack(spacing: 8) {
                        TextField("Yorum ekle…", text: $draft)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(send)
                        Button("Paylaş", action: send)
                            .buttonStyle(.glassProminent)
                            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
                    }
                }
                .padding(12)
            }
            .navigationTitle(post.user.username)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
        .frame(width: 460, height: 700)
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
                    comments.append(comment)
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
                .navigationTitle("Instagram'a Giriş")
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
