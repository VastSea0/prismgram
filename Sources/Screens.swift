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
                    .strokeBorder(.tertiary.opacity(0.65), lineWidth: 1.2)
                    .frame(width: size + gap + stroke, height: size + gap + stroke)
            case .unseen:
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: [
                                Color(red: 0.99, green: 0.78, blue: 0.22),
                                Color(red: 0.99, green: 0.38, blue: 0.24),
                                Color(red: 0.92, green: 0.16, blue: 0.48),
                                Color(red: 0.64, green: 0.20, blue: 0.86),
                                Color(red: 0.92, green: 0.16, blue: 0.48),
                                Color(red: 0.99, green: 0.78, blue: 0.22)
                            ],
                            center: .center
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
            LazyHStack(spacing: 14) {
                ForEach(store.stories) { tray in
                    let isOwn = tray.user.id == store.viewerID
                    StoryTrayCell(tray: tray, isOwn: isOwn) {
                        store.openStory(tray)
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
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(url: tray.user.avatarURL, size: 62, ring: tray.hasUnseen ? .unseen : .seen)
                    if isOwn {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 20, height: 20)
                            .overlay {
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .overlay {
                                Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 2)
                            }
                            .offset(x: -2, y: -2)
                    }
                }
                Text(isOwn ? "Hikayen" : tray.user.username)
                    .font(.system(size: 11.5, weight: tray.hasUnseen ? .medium : .regular))
                    .foregroundStyle(tray.hasUnseen ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(width: 72)
            }
            .scaleEffect(isPressed ? 0.93 : 1.0)
            .animation(.spring(duration: 0.22, bounce: 0.35), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
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

// MARK: - Apple Messages-Style Direct Messages & iOS Instagram Notes

struct MessagesView: View {
    @Bindable var store: AppStore
    @State private var phoneOpenThread: IGDirectThread?
    @State private var searchText = ""

    private var pinnedThreads: [IGDirectThread] {
        filteredThreads.filter(\.isPinned)
    }

    private var filteredThreads: [IGDirectThread] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.directThreads }
        return store.directThreads.filter {
            $0.title.lowercased().contains(q)
                || $0.snippet.lowercased().contains(q)
                || $0.users.contains(where: { $0.username.lowercased().contains(q) })
        }
    }

    var body: some View {
        Group {
            if store.layoutMode == .phone {
                NavigationStack {
                    inboxMasterList(isPhone: true)
                        .navigationDestination(item: $phoneOpenThread) { thread in
                            DirectConversationView(threadID: thread.id, store: store)
                        }
                }
            } else {
                HStack(spacing: 0) {
                    inboxMasterList(isPhone: false)
                        .frame(width: 325)
                    Divider()
                    if let thread = store.selectedThread {
                        DirectConversationView(threadID: thread.id, store: store)
                            .id(thread.id)
                    } else {
                        ContentUnavailableView(
                            "Sohbet Seçin",
                            systemImage: "message",
                            description: Text("Mesajları görüntülemek veya yanıtlamak için soldaki listeden bir sohbet seçin.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .overlay {
            LoadStateView(phase: store.directPhase, isEmpty: store.directThreads.isEmpty && store.notes.isEmpty, emptyTitle: "Mesaj kutusu boş", emptySymbol: "paperplane") {
                Task { await store.refresh(.direct) }
            }
        }
    }

    private func inboxMasterList(isPhone: Bool) -> some View {
        VStack(spacing: 0) {
            // Apple Messages-style search field at top of conversation list
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Sohbetlerde ara", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 8))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().opacity(0.6)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if !store.notes.isEmpty && searchText.isEmpty {
                        NotesBar(store: store)
                        Divider().opacity(0.6)
                    }

                    // Apple Messages-style Pinned Conversations Pod Row when pinned threads exist
                    if !pinnedThreads.isEmpty && searchText.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 18) {
                                ForEach(pinnedThreads) { pinned in
                                    Button {
                                        withAnimation(.snappy(duration: 0.22)) {
                                            store.selectThread(pinned)
                                            if isPhone { phoneOpenThread = pinned }
                                        }
                                    } label: {
                                        VStack(spacing: 6) {
                                            ZStack(alignment: .topTrailing) {
                                                AvatarView(url: pinned.users.first?.avatarURL, size: 54)
                                                    .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
                                                if pinned.isUnread {
                                                    Circle()
                                                        .fill(Color.accentColor)
                                                        .frame(width: 11, height: 11)
                                                        .overlay {
                                                            Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 2)
                                                        }
                                                }
                                            }
                                            Text(pinned.title)
                                                .font(.system(size: 11, weight: .medium))
                                                .lineLimit(1)
                                                .frame(width: 72)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        .scrollIndicators(.hidden)
                        Divider().opacity(0.5)
                    }

                    ForEach(filteredThreads) { thread in
                        let isSelected = !isPhone && store.selectedThread?.id == thread.id
                        InboxThreadRow(
                            thread: thread,
                            isSelected: isSelected
                        ) {
                            withAnimation(.snappy(duration: 0.2)) {
                                store.selectThread(thread)
                                if isPhone { phoneOpenThread = thread }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct InboxThreadRow: View {
    let thread: IGDirectThread
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                // Apple Messages left unread blue indicator dot
                Circle()
                    .fill(thread.isUnread ? Color.accentColor : Color.clear)
                    .frame(width: 8, height: 8)

                AvatarView(url: thread.users.first?.avatarURL, size: 46)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(thread.title)
                            .font(.system(size: 13.5, weight: thread.isUnread ? .bold : .semibold))
                            .foregroundStyle(isSelected ? .white : .primary)
                            .lineLimit(1)

                        if thread.users.first?.isVerified == true {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(isSelected ? .white.opacity(0.9) : .blue)
                        }

                        Spacer(minLength: 4)

                        Text(thread.lastActivityAt, format: .relative(presentation: .named))
                            .font(.system(size: 11))
                            .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
                    }

                    HStack(spacing: 4) {
                        Text(thread.snippet.isEmpty ? "Sohbeti görüntüle" : thread.snippet)
                            .font(.system(size: 12.5, weight: thread.isUnread ? .medium : .regular))
                            .foregroundStyle(
                                isSelected
                                    ? .white.opacity(0.88)
                                    : (thread.isUnread ? .primary : .secondary)
                            )
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        if thread.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(isSelected ? .white.opacity(0.75) : .secondary)
                        }
                    }
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .padding(.horizontal, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// iOS Instagram Notes Bar: thought-bubble callout with two descending circles anchored to the avatar.
struct NotesBar: View {
    @Bindable var store: AppStore

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .bottom, spacing: 16) {
                ForEach(store.notes) { note in
                    Button {
                        store.openProfile(of: note.user)
                    } label: {
                        VStack(spacing: 3) {
                            // Thought bubble + descending tail dots overlapping top of avatar
                            ZStack(alignment: .bottom) {
                                AvatarView(url: note.user.avatarURL, size: 54)
                                    .padding(.top, 26)

                                VStack(alignment: .leading, spacing: 1) {
                                    VStack(spacing: 2) {
                                        if !note.text.isEmpty {
                                            Text(note.text)
                                                .font(.system(size: 11, weight: .medium))
                                                .lineLimit(2)
                                                .multilineTextAlignment(.center)
                                        }
                                        if let music = note.musicTitle, !music.isEmpty {
                                            HStack(spacing: 3) {
                                                Image(systemName: "waveform")
                                                    .font(.system(size: 8, weight: .bold))
                                                    .foregroundStyle(Color.accentColor)
                                                Text(music)
                                                    .font(.system(size: 9.5, weight: .semibold))
                                                    .lineLimit(1)
                                            }
                                            .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: 96)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Color(nsColor: .controlBackgroundColor))
                                            .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                                    }

                                    // Two thought-bubble tail circles
                                    VStack(alignment: .leading, spacing: 1.5) {
                                        Circle()
                                            .fill(Color(nsColor: .controlBackgroundColor))
                                            .frame(width: 7, height: 7)
                                            .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                                        Circle()
                                            .fill(Color(nsColor: .controlBackgroundColor))
                                            .frame(width: 4.5, height: 4.5)
                                            .offset(x: 3)
                                    }
                                    .padding(.leading, 18)
                                }
                                .offset(y: -38)
                            }
                            .frame(height: 82, alignment: .bottom)

                            Text(note.user.id == store.viewerID ? "Notun" : note.user.username)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(width: 74)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Apple Messages Conversation Transcript & Consecutive Bubble Grouping

struct DirectConversationView: View {
    let threadID: String
    @Bindable var store: AppStore
    @State private var draft = ""
    @State private var sendFailed = false

    private var thread: IGDirectThread? {
        store.directThreads.first(where: { $0.id == threadID })
    }

    var body: some View {
        VStack(spacing: 0) {
            if let thread {
                conversationHeader(thread)
                Divider().opacity(0.6)
                messagesTranscript(thread)
                composerBar(thread)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func conversationHeader(_ thread: IGDirectThread) -> some View {
        HStack(spacing: 11) {
            Button {
                if let user = thread.users.first { store.openProfile(of: user) }
            } label: {
                HStack(spacing: 10) {
                    AvatarView(url: thread.users.first?.avatarURL, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(thread.title)
                                .font(.system(size: 13.5, weight: .semibold))
                            if thread.users.first?.isVerified == true {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.blue)
                            }
                        }
                        if let username = thread.users.first?.username {
                            Text("@\(username)")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if let user = thread.users.first {
                Button {
                    store.openProfile(of: user)
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15))
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("Profil bilgilerini aç")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func messagesTranscript(_ thread: IGDirectThread) -> some View {
        let msgs = thread.messages

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Conversation identity card at top of transcript (like iOS Instagram DM / Apple Messages)
                    if let peer = thread.users.first {
                        VStack(spacing: 8) {
                            AvatarView(url: peer.avatarURL, size: 68)
                            VStack(spacing: 2) {
                                Text(thread.title)
                                    .font(.system(size: 15, weight: .semibold))
                                Text("@\(peer.username) · Instagram")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Button("Profili Gör") {
                                store.openProfile(of: peer)
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                            .padding(.top, 2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }

                    ForEach(Array(msgs.enumerated()), id: \.element.id) { index, message in
                        let prev: IGDirectMessage? = index > 0 ? msgs[index - 1] : nil
                        let next: IGDirectMessage? = index + 1 < msgs.count ? msgs[index + 1] : nil

                        let showTimestampHeader = prev == nil || message.timestamp.timeIntervalSince(prev!.timestamp) > 900
                        let sameAsPrev = !showTimestampHeader
                            && prev?.isFromViewer == message.isFromViewer
                            && prev?.senderFBID == message.senderFBID
                        let sameAsNext = next != nil
                            && next!.timestamp.timeIntervalSince(message.timestamp) <= 900
                            && next?.isFromViewer == message.isFromViewer
                            && next?.senderFBID == message.senderFBID

                        VStack(spacing: 0) {
                            if showTimestampHeader {
                                Text(message.timestamp, format: .dateTime.day().month(.abbreviated).hour().minute())
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 14)
                                    .padding(.bottom, 8)
                            }

                            MessageBubbleRow(
                                message: message,
                                fallbackAvatar: thread.users.first?.avatarURL,
                                isFirstInGroup: !sameAsPrev,
                                isLastInGroup: !sameAsNext
                            )
                            .padding(.top, sameAsPrev ? 2 : 9)
                        }
                        .id(message.id)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.92, anchor: message.isFromViewer ? .bottomTrailing : .bottomLeading).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
            .onChange(of: msgs.count, initial: true) { _, _ in
                if let lastID = msgs.last?.id {
                    withAnimation(.spring(duration: 0.28, bounce: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    /// Apple Messages capsule composer with integrated circular up-arrow send button.
    private func composerBar(_ thread: IGDirectThread) -> some View {
        let canSend = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.isSendingDirectMessage

        return VStack(alignment: .leading, spacing: 4) {
            if sendFailed {
                Text("Mesaj gönderilemedi. Yeniden deneyin.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 6)
            }

            HStack(spacing: 8) {
                Button {
                    Task { _ = await store.sendDirectMessage(text: "❤️", in: thread) }
                } label: {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Kalp gönder")

                HStack(spacing: 6) {
                    TextField("Mesaj…", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13.5))
                        .onSubmit { send(in: thread) }

                    Button {
                        send(in: thread)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 24))
                            .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.4))
                            .scaleEffect(canSend ? 1.0 : 0.88)
                            .animation(.spring(duration: 0.22, bounce: 0.35), value: canSend)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                }
                .padding(.leading, 12)
                .padding(.trailing, 5)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay {
                    Capsule()
                        .strokeBorder(.primary.opacity(0.14), lineWidth: 0.8)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func send(in thread: IGDirectThread) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !store.isSendingDirectMessage else { return }
        sendFailed = false
        let copy = text
        draft = ""
        Task {
            let ok = await store.sendDirectMessage(text: copy, in: thread)
            if !ok {
                draft = copy
                sendFailed = true
            }
        }
    }
}

/// Renders an individual bubble following Apple Messages / iOS Instagram DM consecutive grouping geometry.
private struct MessageBubbleRow: View {
    let message: IGDirectMessage
    let fallbackAvatar: URL?
    let isFirstInGroup: Bool
    let isLastInGroup: Bool

    private var bubbleRadii: RectangleCornerRadii {
        let big: CGFloat = 18
        let tight: CGFloat = 5
        if message.isFromViewer {
            return RectangleCornerRadii(
                topLeading: big,
                bottomLeading: big,
                bottomTrailing: isLastInGroup ? tight : tight,
                topTrailing: isFirstInGroup ? big : tight
            )
        } else {
            return RectangleCornerRadii(
                topLeading: isFirstInGroup ? big : tight,
                bottomLeading: isLastInGroup ? tight : tight,
                bottomTrailing: big,
                topTrailing: big
            )
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isFromViewer {
                Spacer(minLength: 60)
            } else {
                if isLastInGroup {
                    AvatarView(url: message.senderAvatarURL ?? fallbackAvatar, size: 26)
                } else {
                    Color.clear.frame(width: 26, height: 26)
                }
            }

            Text(message.text)
                .font(.system(size: 13.5))
                .foregroundStyle(message.isFromViewer ? Color.white : Color.primary)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(
                    UnevenRoundedRectangle(cornerRadii: bubbleRadii, style: .continuous)
                        .fill(
                            message.isFromViewer
                                ? AnyShapeStyle(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.34, green: 0.38, blue: 0.98),
                                            Color(red: 0.08, green: 0.52, blue: 0.99)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                : AnyShapeStyle(.quaternary.opacity(0.85))
                        )
                )
                .help(message.timestamp.formatted(date: .abbreviated, time: .shortened))

            if !message.isFromViewer {
                Spacer(minLength: 60)
            }
        }
    }
}
