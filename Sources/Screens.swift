import SwiftUI
import AVKit

// MARK: - Brand & Shared Building Blocks

struct PrismMark: View {
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [
                            Color(red: 0.98, green: 0.36, blue: 0.34),
                            Color(red: 0.99, green: 0.68, blue: 0.24),
                            Color(red: 0.30, green: 0.68, blue: 0.98),
                            Color(red: 0.62, green: 0.36, blue: 0.98),
                            Color(red: 0.96, green: 0.30, blue: 0.66),
                            Color(red: 0.98, green: 0.36, blue: 0.34)
                        ],
                        center: .center
                    ),
                    lineWidth: size * 0.14
                )
                .frame(width: size, height: size)

            Circle()
                .fill(.primary.opacity(0.85))
                .frame(width: size * 0.34, height: size * 0.34)
        }
    }
}

struct AvatarView: View {
    let url: URL?
    var size: CGFloat = 36
    var ring: Ring = .none

    enum Ring { case none, seen, unseen }

    var body: some View {
        let gap: CGFloat = size >= 52 ? 6 : 4
        let stroke: CGFloat = size >= 52 ? 2.4 : 1.8

        ZStack {
            switch ring {
            case .none:
                EmptyView()
            case .seen:
                Circle()
                    .strokeBorder(Color(light: 0xDBDBDB, dark: 0x3A3A3A), lineWidth: 1)
                    .frame(width: size + gap + stroke, height: size + gap + stroke)
            case .unseen:
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color(hex: 0xFEDA75),
                                Color(hex: 0xFA7E1E),
                                Color(hex: 0xD62976),
                                Color(hex: 0x962FBF),
                                Color(hex: 0x4F5BD5)
                            ],
                            startPoint: .bottomLeading,
                            endPoint: .topTrailing
                        ),
                        lineWidth: stroke
                    )
                    .frame(width: size + gap + stroke, height: size + gap + stroke)
            }

            CachedImage(url: url, maxPixelSize: size * 3) { _ in
                Circle().fill(.quaternary)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.42))
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
            }
        }
    }
}

struct RemoteImage: View {
    let url: URL?
    var maxPixelSize: CGFloat = 1080

    var body: some View {
        CachedImage(url: url, maxPixelSize: maxPixelSize) { failed in
            Rectangle().fill(.quaternary.opacity(failed ? 1 : 0.6))
                .overlay {
                    if failed { Image(systemName: "photo").foregroundStyle(.secondary) }
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

// MARK: - Post & Media Pager (Instagram iOS layout + double-tap heart burst)

struct MediaPager: View {
    let items: [IGMediaItem]
    @Binding var currentIndex: Int
    var onDoubleTap: () -> Void = {}

    @State private var pageID: String?
    @State private var showHeartBurst = false
    @State private var heartScale: CGFloat = 0.3
    @State private var heartOpacity: Double = 0

    private var ratio: Double { items.first?.aspectRatio ?? 1 }

    var body: some View {
        ZStack {
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
            .scrollPosition(id: $pageID)
            .onChange(of: pageID) { _, newValue in
                if let newValue, let idx = items.firstIndex(where: { $0.id == newValue }) {
                    withAnimation(.spring(duration: 0.25)) {
                        currentIndex = idx
                    }
                }
            }

            if showHeartBurst {
                Image(systemName: "heart.fill")
                    .font(.system(size: 86, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.24, blue: 0.38), Color(red: 0.98, green: 0.12, blue: 0.52)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
                    .scaleEffect(heartScale)
                    .opacity(heartOpacity)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            if items.count > 1 {
                Text("\(currentIndex + 1)/\(items.count)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.62), in: .capsule)
                    .padding(12)
            }
        }
        .contentShape(.rect)
        .onTapGesture(count: 2) {
            onDoubleTap()
            triggerHeartBurst()
        }
    }

    private func triggerHeartBurst() {
        showHeartBurst = true
        heartScale = 0.35
        heartOpacity = 1.0
        withAnimation(.spring(duration: 0.38, bounce: 0.48)) {
            heartScale = 1.08
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(520))
            withAnimation(.easeOut(duration: 0.22)) {
                heartOpacity = 0
                heartScale = 1.24
            }
            try? await Task.sleep(for: .milliseconds(240))
            showHeartBurst = false
        }
    }
}

struct PostView: View {
    let post: IGPost
    @Bindable var store: AppStore
    var showsCommentLink = true

    @State private var isCaptionExpanded = false
    @State private var currentSlide = 0

    var body: some View {
        let isPhone = store.layoutMode == .phone

        VStack(alignment: .leading, spacing: 10) {
            header
                .padding(.horizontal, 14)

            MediaPager(items: post.items, currentIndex: $currentSlide) {
                if !post.hasLiked { store.toggleLike(post) }
            }
            .clipShape(.rect(cornerRadius: isPhone ? 0 : 10))
            .overlay {
                if !isPhone {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                }
            }
            .padding(.horizontal, isPhone ? 0 : 12)

            actions
                .padding(.horizontal, 14)

            VStack(alignment: .leading, spacing: 5) {
                if post.likeCount > 0 {
                    Text("\(post.likeCount.formatted()) beğenme")
                        .font(.system(size: 13.5, weight: .semibold))
                        .contentTransition(.numericText(value: Double(post.likeCount)))
                }

                if !post.caption.isEmpty {
                    Text("**\(post.user.username)**  \(post.caption)")
                        .font(.system(size: 13.5))
                        .lineLimit(isCaptionExpanded ? nil : 2)
                        .onTapGesture {
                            withAnimation(.snappy(duration: 0.22)) {
                                isCaptionExpanded.toggle()
                            }
                        }
                }

                if showsCommentLink && post.commentCount > 0 {
                    Button("\(post.commentCount.formatted()) yorumun tümünü gör") {
                        store.detailPost = post
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                }

                Text(post.takenAt, format: .relative(presentation: .named))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
            }
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 11)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { store.openProfile(of: post.user) } label: {
                HStack(spacing: 10) {
                    AvatarView(url: post.user.avatarURL, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(post.user.username)
                                .font(.system(size: 13.5, weight: .semibold))
                            if post.user.isVerified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.blue)
                            }
                        }
                        if let location = post.locationName {
                            Text(location)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Menu {
                Button {
                    store.openProfile(of: post.user)
                } label: {
                    Label("@\(post.user.username) Profilini Aç", systemImage: "person.crop.circle")
                }
                Button {
                    NSWorkspace.shared.open(permalink)
                } label: {
                    Label("Tarayıcıda Aç", systemImage: "safari")
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(permalink.absoluteString, forType: .string)
                } label: {
                    Label("Bağlantıyı Kopyala", systemImage: "link")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var actions: some View {
        ZStack {
            // Centered iOS Instagram carousel indicator dots
            if post.items.count > 1 {
                HStack(spacing: 4) {
                    ForEach(post.items.indices, id: \.self) { idx in
                        let active = idx == currentSlide
                        Circle()
                            .fill(active ? Color.accentColor : Color.secondary.opacity(0.32))
                            .frame(width: active ? 6 : 4.5, height: active ? 6 : 4.5)
                            .animation(.spring(duration: 0.22), value: currentSlide)
                    }
                }
            }

            HStack(spacing: 16) {
                Button {
                    withAnimation(.spring(duration: 0.3, bounce: 0.5)) {
                        store.toggleLike(post)
                    }
                } label: {
                    Image(systemName: post.hasLiked ? "heart.fill" : "heart")
                        .foregroundStyle(post.hasLiked ? Color(red: 1.0, green: 0.19, blue: 0.25) : Color.primary)
                        .symbolEffect(.bounce, value: post.hasLiked)
                }

                Button { store.detailPost = post } label: {
                    Image(systemName: "bubble.right")
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(permalink.absoluteString, forType: .string)
                } label: {
                    Image(systemName: "paperplane")
                }
                .help("Bağlantıyı kopyala")

                Spacer()

                Button {
                    withAnimation(.spring(duration: 0.28, bounce: 0.4)) {
                        store.toggleSave(post)
                    }
                } label: {
                    Image(systemName: post.hasSaved ? "bookmark.fill" : "bookmark")
                        .symbolEffect(.bounce, value: post.hasSaved)
                }
            }
            .font(.system(size: 19, weight: .regular))
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
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
                    Divider().opacity(0.6)
                }

                ForEach(store.feed) { post in
                    PostView(post: post, store: store)
                        .onAppear {
                            if post.id == store.feed.last?.id {
                                Task { await store.loadMoreFeed() }
                            }
                        }
                    Divider().opacity(0.5)
                }

                if store.isLoadingMoreFeed {
                    ProgressView().padding(20)
                }
            }
            .frame(maxWidth: store.layoutMode == .phone ? .infinity : 540)
            .frame(maxWidth: .infinity)
        }
        .overlay {
            LoadStateView(phase: store.feedPhase, isEmpty: store.feed.isEmpty, emptyTitle: "Akışınız boş", emptySymbol: "house") {
                Task { await store.refresh(.home) }
            }
        }
    }
}

/// iOS Instagram Story Tray: 64pt avatars, gradient unseen ring, "+" badge on viewer's own story.
struct StoryTray: View {
    @Bindable var store: AppStore

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 10) {
                ForEach(store.stories) { tray in
                    let isOwn = tray.user.id == store.viewerID
                    StoryTrayCell(tray: tray, isOwn: isOwn) {
                        store.openStory(tray, in: store.stories)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .scrollIndicators(.hidden)
    }
}

private struct StoryTrayCell: View {
    let tray: IGStoryTray
    let isOwn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                AvatarView(url: tray.user.avatarURL, size: 62, ring: tray.hasUnseen ? .unseen : .seen)
                    .frame(width: 72, height: 72)
                    .overlay(alignment: .bottomTrailing) {
                        if isOwn {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Color.igBlue))
                                .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 2.5))
                                .offset(x: -2, y: -2)
                        }
                    }
                Text(isOwn ? "Hikayen" : tray.user.username)
                    .font(.system(size: 12))
                    .foregroundStyle(tray.hasUnseen || isOwn ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(width: 74)
            }
        }
        .buttonStyle(PressableButtonStyle())
    }
}

// MARK: - Explore (3:4 portrait tiles with hover engagement overlay)

struct ExploreView: View {
    @Bindable var store: AppStore
    @State private var filterText = ""

    private var filteredPosts: [IGPost] {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.explore }
        return store.explore.filter {
            $0.user.username.lowercased().contains(q)
                || $0.user.fullName.lowercased().contains(q)
                || $0.caption.lowercased().contains(q)
                || ($0.locationName?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: store.layoutMode == .phone ? 120 : 175), spacing: 2)], spacing: 2) {
                ForEach(filteredPosts) { post in
                    MediaGridTile(post: post) {
                        store.detailPost = post
                    }
                }
            }
            .padding(2)
        }
        .searchable(text: $filterText, prompt: "Keşfet'te filtrele…")
        .overlay {
            LoadStateView(phase: store.explorePhase, isEmpty: store.explore.isEmpty, emptyTitle: "Keşfet boş", emptySymbol: "magnifyingglass") {
                Task { await store.refresh(.explore) }
            }
        }
    }
}

/// Grid tile of the Instagram for iOS profile and explore grids, with macOS hover stats.
struct MediaGridTile: View {
    let post: IGPost
    var aspectRatio: CGFloat = 3.0 / 4.0
    var showsViewCount = false
    var showsPin = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Color.clear
                .aspectRatio(aspectRatio, contentMode: .fit)
                .overlay {
                    RemoteImage(url: post.items.first?.thumbURL, maxPixelSize: 480)
                        .scaleEffect(isHovered ? 1.03 : 1.0)
                }
                .overlay(alignment: .topTrailing) {
                    Group {
                        if showsPin && post.isPinned {
                            Image(systemName: "pin.fill").rotationEffect(.degrees(45))
                        } else if post.isVideo && !showsViewCount {
                            Image(systemName: "play.rectangle.fill")
                        } else if post.items.count > 1 {
                            Image(systemName: "square.fill.on.square.fill")
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                    .padding(8)
                }
                .overlay(alignment: .bottomLeading) {
                    if showsViewCount, let views = post.viewCount {
                        Label(views.igCompact, systemImage: "play")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                            .padding(8)
                    }
                }
                .overlay {
                    if isHovered {
                        Color.black.opacity(0.38)
                            .overlay {
                                HStack(spacing: 16) {
                                    Label(post.likeCount.igCompact, systemImage: "heart.fill")
                                    Label(post.commentCount.igCompact, systemImage: "bubble.right.fill")
                                }
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                            }
                            .transition(.opacity)
                    }
                }
                .clipped()
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) {
                isHovered = hovering
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

            LinearGradient(
                colors: [.clear, .black.opacity(0.65)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(height: 220)
            .allowsHitTesting(false)

            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Button { store.openProfile(of: reel.user) } label: {
                        HStack(spacing: 9) {
                            AvatarView(url: reel.user.avatarURL, size: 32)
                            Text(reel.user.username)
                                .font(.system(size: 14, weight: .semibold))
                            if reel.user.isVerified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    if !reel.caption.isEmpty {
                        Text(reel.caption)
                            .font(.system(size: 13))
                            .lineLimit(2)
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                .padding(.bottom, store.layoutMode == .phone ? 64 : 24)

                Spacer()

                VStack(spacing: 14) {
                    Button {
                        withAnimation(.spring(duration: 0.3, bounce: 0.5)) {
                            store.toggleLike(reel)
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: reel.hasLiked ? "heart.fill" : "heart")
                                .font(.system(size: 20))
                                .foregroundStyle(reel.hasLiked ? Color(red: 1.0, green: 0.19, blue: 0.25) : Color.primary)
                                .symbolEffect(.bounce, value: reel.hasLiked)
                            Text(reel.likeCount.formatted(.number.notation(.compactName)))
                                .font(.system(size: 11, weight: .medium))
                        }
                        .frame(width: 46, height: 52)
                    }
                    Button { store.detailPost = reel } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "bubble.right")
                                .font(.system(size: 19))
                            Text(reel.commentCount.formatted(.number.notation(.compactName)))
                                .font(.system(size: 11, weight: .medium))
                        }
                        .frame(width: 46, height: 52)
                    }
                    Button {
                        withAnimation(.spring(duration: 0.28, bounce: 0.4)) {
                            store.toggleSave(reel)
                        }
                    } label: {
                        Image(systemName: reel.hasSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 18))
                            .frame(width: 46, height: 38)
                            .symbolEffect(.bounce, value: reel.hasSaved)
                    }
                }
                .buttonStyle(.glass)
                .padding(.bottom, store.layoutMode == .phone ? 64 : 24)
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Activity

struct ActivityView: View {
    @Bindable var store: AppStore

    var body: some View {
        List(store.activity) { item in
            HStack(spacing: 12) {
                AvatarView(url: item.avatarURL, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.text)
                        .font(.system(size: 13))
                        .lineLimit(3)
                    if let date = item.date {
                        Text(date, format: .relative(presentation: .named))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 6)
                if let thumb = item.thumbURL {
                    RemoteImage(url: thumb, maxPixelSize: 128)
                        .frame(width: 42, height: 42)
                        .clipShape(.rect(cornerRadius: 6))
                }
            }
            .padding(.vertical, 4)
        }
        .overlay {
            LoadStateView(phase: store.activityPhase, isEmpty: store.activity.isEmpty, emptyTitle: "Bildirim yok", emptySymbol: "heart") {
                Task { await store.refresh(.activity) }
            }
        }
        .task { await store.ensureLoaded(.activity) }
    }
}
