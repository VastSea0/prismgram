import SwiftUI
import AVKit

// MARK: - Shared building blocks

struct AvatarView: View {
    let url: URL?
    var size: CGFloat = 36
    var ring: Ring = .none

    enum Ring { case none, seen, unseen }

    var body: some View {
        ZStack {
            switch ring {
            case .none:
                EmptyView()
            case .seen:
                Circle().strokeBorder(.quaternary, lineWidth: 1.5)
                    .frame(width: size + 8, height: size + 8)
            case .unseen:
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [.orange, .pink, .purple],
                            startPoint: .bottomLeading,
                            endPoint: .topTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: size + 8, height: size + 8)
            }

            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Circle().fill(.quaternary)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: size * 0.42))
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        }
    }
}

struct RemoteImage: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                Rectangle().fill(.quaternary)
                    .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
            default:
                Rectangle().fill(.quaternary)
            }
        }
    }
}

/// AppKit's AVPlayerView, wrapped directly. (SwiftUI's `VideoPlayer` aborts at metadata load on this OS build.)
struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer
    var showsControls = true
    var fillsFrame = true

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = showsControls ? .inline : .none
        view.videoGravity = fillsFrame ? .resizeAspectFill : .resizeAspect
        view.showsFullScreenToggleButton = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player { nsView.player = player }
    }
}

struct InlineVideo: View {
    let url: URL
    var autoplay = false
    var muted = true
    var showsControls = true
    var fillsFrame = true

    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                PlayerSurface(player: player, showsControls: showsControls, fillsFrame: fillsFrame)
            } else {
                Color.black
            }
        }
        .onAppear {
            if player == nil {
                let newPlayer = AVPlayer(url: url)
                newPlayer.isMuted = muted
                player = newPlayer
            }
            if autoplay { player?.play() }
        }
        .onDisappear { player?.pause() }
    }
}

struct LoadStateView: View {
    let phase: AppStore.Phase
    let isEmpty: Bool
    var emptyTitle = "Gösterilecek içerik yok"
    var emptySymbol = "tray"
    let retry: () -> Void

    var body: some View {
        switch phase {
        case .idle, .loading:
            if isEmpty { ProgressView().controlSize(.large) }
        case .failed(let message):
            if isEmpty {
                ContentUnavailableView {
                    Label("Yüklenemedi", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Tekrar Dene", action: retry)
                }
            }
        case .loaded:
            if isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: emptySymbol)
            }
        }
    }
}

// MARK: - Post

struct MediaPager: View {
    let items: [IGMediaItem]
    var onDoubleTap: () -> Void = {}

    @State private var page: String?

    private var ratio: Double { items.first?.aspectRatio ?? 1 }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(items) { item in
                    Group {
                        if let video = item.videoURL {
                            InlineVideo(url: video)
                        } else {
                            RemoteImage(url: item.imageURL)
                        }
                    }
                    .containerRelativeFrame(.horizontal)
                    .aspectRatio(ratio, contentMode: .fit)
                    .clipped()
                    .id(item.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $page)
        .overlay(alignment: .topTrailing) {
            if items.count > 1 {
                let current = (items.firstIndex(where: { $0.id == page }) ?? 0) + 1
                Text("\(current)/\(items.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: .capsule)
                    .padding(10)
            }
        }
        .onTapGesture(count: 2, perform: onDoubleTap)
    }
}

struct PostView: View {
    let post: IGPost
    @Bindable var store: AppStore
    var showsCommentLink = true

    @State private var isCaptionExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
                .padding(.horizontal, 14)

            MediaPager(items: post.items) {
                if !post.hasLiked { store.toggleLike(post) }
            }
            .clipShape(.rect(cornerRadius: 12))
            .padding(.horizontal, 12)

            actions
                .padding(.horizontal, 14)

            VStack(alignment: .leading, spacing: 6) {
                if post.likeCount > 0 {
                    Text("\(post.likeCount.formatted()) beğenme")
                        .font(.subheadline.weight(.semibold))
                }

                if !post.caption.isEmpty {
                    Text("**\(post.user.username)**  \(post.caption)")
                        .font(.subheadline)
                        .lineLimit(isCaptionExpanded ? nil : 3)
                        .onTapGesture { isCaptionExpanded.toggle() }
                }

                if showsCommentLink && post.commentCount > 0 {
                    Button("\(post.commentCount.formatted()) yorumun tümünü gör") {
                        store.detailPost = post
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Text(post.takenAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 12)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { store.openProfile(of: post.user) } label: {
                HStack(spacing: 10) {
                    AvatarView(url: post.user.avatarURL, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(post.user.username).font(.subheadline.weight(.semibold))
                            if post.user.isVerified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        }
                        if let location = post.locationName {
                            Text(location).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    private var actions: some View {
        HStack(spacing: 18) {
            Button { store.toggleLike(post) } label: {
                Image(systemName: post.hasLiked ? "heart.fill" : "heart")
                    .foregroundStyle(post.hasLiked ? Color.red : Color.primary)
            }
            Button { store.detailPost = post } label: {
                Image(systemName: "bubble.right")
            }
            Button { NSWorkspace.shared.open(permalink) } label: {
                Image(systemName: "arrow.up.right.square")
            }
            .help("Instagram'da aç")
            Spacer()
            Button { store.toggleSave(post) } label: {
                Image(systemName: post.hasSaved ? "bookmark.fill" : "bookmark")
            }
        }
        .font(.title3)
        .buttonStyle(.plain)
    }

    private var permalink: URL {
        URL(string: "https://www.instagram.com/p/\(post.code)/") ?? URL(string: "https://www.instagram.com/")!
    }
}

// MARK: - Home

struct HomeView: View {
    @Bindable var store: AppStore

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !store.stories.isEmpty {
                    StoryTray(store: store)
                    Divider()
                }

                ForEach(store.feed) { post in
                    PostView(post: post, store: store)
                        .onAppear {
                            if post.id == store.feed.last?.id {
                                Task { await store.loadMoreFeed() }
                            }
                        }
                    Divider()
                }

                if store.isLoadingMoreFeed {
                    ProgressView().padding()
                }
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .overlay {
            LoadStateView(phase: store.feedPhase, isEmpty: store.feed.isEmpty, emptyTitle: "Akışınız boş", emptySymbol: "house") {
                Task { await store.refresh(.home) }
            }
        }
    }
}

struct StoryTray: View {
    @Bindable var store: AppStore

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 14) {
                ForEach(store.stories.filter { !$0.slides.isEmpty }) { tray in
                    Button {
                        store.markStorySeen(tray.id)
                        store.storyViewer = tray
                    } label: {
                        VStack(spacing: 6) {
                            AvatarView(url: tray.user.avatarURL, size: 54, ring: tray.hasUnseen ? .unseen : .seen)
                            Text(tray.user.id == store.viewerID ? "Hikayen" : tray.user.username)
                                .font(.caption)
                                .lineLimit(1)
                                .frame(width: 68)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Explore

struct ExploreView: View {
    @Bindable var store: AppStore

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 2)], spacing: 2) {
                ForEach(store.explore) { post in
                    Button { store.detailPost = post } label: {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay { RemoteImage(url: post.items.first?.thumbURL) }
                            .overlay(alignment: .topTrailing) {
                                if post.isVideo {
                                    Image(systemName: "play.fill")
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                        .shadow(radius: 2)
                                        .padding(6)
                                } else if post.items.count > 1 {
                                    Image(systemName: "square.on.square")
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                        .shadow(radius: 2)
                                        .padding(6)
                                }
                            }
                            .clipped()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
        }
        .overlay {
            LoadStateView(phase: store.explorePhase, isEmpty: store.explore.isEmpty, emptyTitle: "Keşfet boş", emptySymbol: "magnifyingglass") {
                Task { await store.refresh(.explore) }
            }
        }
    }
}

// MARK: - Reels

struct ReelsView: View {
    @Bindable var store: AppStore

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(store.reels) { reel in
                    ReelPage(reel: reel, store: store)
                        .containerRelativeFrame(.vertical)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .background(.black)
        .overlay {
            LoadStateView(phase: store.reelsPhase, isEmpty: store.reels.isEmpty, emptyTitle: "Reels bulunamadı", emptySymbol: "play.rectangle") {
                Task { await store.refresh(.reels) }
            }
        }
    }
}

struct ReelPage: View {
    let reel: IGPost
    @Bindable var store: AppStore

    var body: some View {
        ZStack(alignment: .bottom) {
            if let url = reel.items.first?.videoURL {
                InlineVideo(url: url, autoplay: true, muted: false, fillsFrame: false)
            } else {
                Color.black
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Button { store.openProfile(of: reel.user) } label: {
                        HStack(spacing: 8) {
                            AvatarView(url: reel.user.avatarURL, size: 28)
                            Text(reel.user.username).font(.subheadline.weight(.semibold))
                        }
                    }
                    .buttonStyle(.plain)

                    if !reel.caption.isEmpty {
                        Text(reel.caption).font(.footnote).lineLimit(2)
                    }
                }
                .foregroundStyle(.white)
                .shadow(radius: 3)
                .padding(.bottom, 54)

                Spacer()

                VStack(spacing: 12) {
                    Button { store.toggleLike(reel) } label: {
                        VStack(spacing: 2) {
                            Image(systemName: reel.hasLiked ? "heart.fill" : "heart")
                                .foregroundStyle(reel.hasLiked ? Color.red : Color.primary)
                            Text(reel.likeCount.formatted(.number.notation(.compactName))).font(.caption2)
                        }
                        .frame(width: 44, height: 50)
                    }
                    Button { store.detailPost = reel } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "bubble.right")
                            Text(reel.commentCount.formatted(.number.notation(.compactName))).font(.caption2)
                        }
                        .frame(width: 44, height: 50)
                    }
                    Button { store.toggleSave(reel) } label: {
                        Image(systemName: reel.hasSaved ? "bookmark.fill" : "bookmark")
                            .frame(width: 44, height: 36)
                    }
                }
                .buttonStyle(.glass)
                .padding(.bottom, 54)
            }
            .padding(.horizontal, 14)
        }
    }
}

// MARK: - Activity & Messages

struct ActivityView: View {
    @Bindable var store: AppStore

    var body: some View {
        List(store.activity) { item in
            HStack(spacing: 10) {
                AvatarView(url: item.avatarURL, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.text).font(.subheadline).lineLimit(3)
                    if let date = item.date {
                        Text(date, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                if let thumb = item.thumbURL {
                    RemoteImage(url: thumb)
                        .frame(width: 38, height: 38)
                        .clipShape(.rect(cornerRadius: 6))
                }
            }
            .padding(.vertical, 2)
        }
        .overlay {
            LoadStateView(phase: store.activityPhase, isEmpty: store.activity.isEmpty, emptyTitle: "Bildirim yok", emptySymbol: "heart") {
                Task { await store.refresh(.activity) }
            }
        }
        .task { await store.ensureLoaded(.activity) }
    }
}

struct MessagesView: View {
    @Bindable var store: AppStore

    var body: some View {
        ContentUnavailableView {
            Label("Mesajlar", systemImage: "paperplane")
        } description: {
            Text("Instagram, doğrudan mesajlar için uygulama dışı erişime izin veren bir arayüz sunmuyor. Mesajlarınız tarayıcıda açılır.")
        } actions: {
            Button("Tarayıcıda Aç") { store.openMessagesInBrowser() }
                .buttonStyle(.glassProminent)
        }
    }
}

// MARK: - Profile

struct ProfileView: View {
    @Bindable var store: AppStore

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let user = store.profile {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 20) {
                            AvatarView(url: user.avatarURL, size: 84)
                            HStack(spacing: 22) {
                                stat(user.mediaCount, "gönderi")
                                stat(user.followerCount, "takipçi")
                                stat(user.followingCount, "takip")
                            }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Text(user.fullName.isEmpty ? user.username : user.fullName)
                                    .font(.headline)
                                if user.isVerified {
                                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue)
                                }
                            }
                            Text("@\(user.username)").font(.subheadline).foregroundStyle(.secondary)
                            if !user.biography.isEmpty {
                                Text(user.biography).font(.subheadline)
                            }
                        }
                    }
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 2)], spacing: 2) {
                        ForEach(store.profilePosts) { post in
                            Button { store.detailPost = post } label: {
                                Color.clear
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay { RemoteImage(url: post.items.first?.thumbURL) }
                                    .clipped()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                }
            }
        }
        .overlay {
            LoadStateView(phase: store.profilePhase, isEmpty: store.profile == nil, emptyTitle: "Profil bulunamadı", emptySymbol: "person.crop.circle") {
                Task { await store.refresh(.profile) }
            }
        }
    }

    private func stat(_ value: Int?, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value.map { $0.formatted(.number.notation(.compactName)) } ?? "–")
                .font(.headline)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
