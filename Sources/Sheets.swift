import SwiftUI
import WebKit
import AppKit

// MARK: - Story viewer (9:16 iOS Instagram story canvas + animated scrub bars)

struct StoryViewer: View {
    let tray: IGStoryTray
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var slideProgress: CGFloat = 0

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
                        InlineVideo(url: video, autoplay: true, muted: false, showsControls: false, fillsFrame: true)
                            .allowsHitTesting(false)
                    } else {
                        RemoteImage(url: slide.imageURL)
                    }
                }
                .frame(width: 400, height: 710)
                .clipped()
                .id(slide.id)
                .transition(.opacity.animation(.easeOut(duration: 0.18)))
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

            // Left / right tap zones for previous / next slide
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: 130)
                    .contentShape(.rect)
                    .onTapGesture { step(-1) }
                Color.clear
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                    .onTapGesture { step(1) }
            }

            VStack(spacing: 11) {
                if !activeTray.slides.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(activeTray.slides.indices, id: \.self) { position in
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.white.opacity(0.32))
                                    Capsule()
                                        .fill(Color.white)
                                        .frame(
                                            width: geo.size.width * fillFraction(for: position)
                                        )
                                }
                            }
                            .frame(height: 2.5)
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
                            AvatarView(url: activeTray.user.avatarURL, size: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text(activeTray.title ?? activeTray.user.username)
                                        .font(.system(size: 13.5, weight: .semibold))
                                        .foregroundStyle(.white)
                                    if activeTray.user.isVerified {
                                        Image(systemName: "checkmark.seal.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.white)
                                    }
                                }
                                if activeTray.title != nil {
                                    Text("@\(activeTray.user.username)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.75))
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding(14)
            .background(
                LinearGradient(colors: [.black.opacity(0.62), .clear], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
            )
        }
        .frame(width: 400, height: 710)
        .task(id: "\(activeTray.slides.count)-\(index)") {
            guard !activeTray.slides.isEmpty else { return }
            let duration: Double = slide?.videoURL == nil ? 6.0 : 12.0
            slideProgress = 0
            withAnimation(.linear(duration: duration)) {
                slideProgress = 1.0
            }
            try? await Task.sleep(for: .seconds(duration))
            if !Task.isCancelled { step(1) }
        }
        .onDisappear { store.storyViewer = nil }
    }

    private func fillFraction(for position: Int) -> CGFloat {
        if position < index { return 1.0 }
        if position > index { return 0.0 }
        return slideProgress
    }

    private func step(_ delta: Int) {
        guard !activeTray.slides.isEmpty else { return }
        let next = index + delta
        if next < 0 {
            slideProgress = 0
            index = 0
        } else if next >= activeTray.slides.count {
            dismiss()
        } else {
            slideProgress = 0
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
