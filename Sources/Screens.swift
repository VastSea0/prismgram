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

/// A looping, chrome-less video like Instagram's feed and Reels. The player is released when the view
/// leaves the screen so a long feed does not keep dozens of decoders alive.
struct LoopingVideo: View {
    let url: URL
    var isPlaying: Bool
    var isMuted: Bool
    var fillsFrame = true

    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        ZStack {
            Color.black
            if let player {
                PlayerSurface(player: player, showsControls: false, fillsFrame: fillsFrame)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            if player == nil {
                let queue = AVQueuePlayer()
                looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
                player = queue
            }
            apply()
        }
        .onDisappear {
            player?.pause()
            looper?.disableLooping()
            looper = nil
            player = nil
        }
        .onChange(of: isPlaying) { _, _ in apply() }
        .onChange(of: isMuted) { _, _ in apply() }
    }

    private func apply() {
        guard let player else { return }
        player.isMuted = isMuted
        if isPlaying { player.play() } else { player.pause() }
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
    var isVisible = true
    var onDoubleTap: () -> Void = {}

    @AppStorage("feedVideosMuted") private var isMuted = true
    @State private var pageID: String?
    @State private var isHovering = false
    @State private var showHeartBurst = false
    @State private var heartScale: CGFloat = 0.3
    @State private var heartOpacity: Double = 0

    /// Instagram sizes the whole carousel by its first item.
    private var ratio: Double { items.first?.aspectRatio ?? 1 }
    private var current: IGMediaItem? { items[safe: currentIndex] }

    var body: some View {
        Color.clear
            .aspectRatio(ratio, contentMode: .fit)
            .overlay {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            Group {
                                if let video = item.videoURL {
                                    LoopingVideo(url: video, isPlaying: isVisible && index == currentIndex, isMuted: isMuted)
                                } else {
                                    RemoteImage(url: item.imageURL)
                                }
                            }
                            .containerRelativeFrame([.horizontal, .vertical])
                            .clipped()
                            .id(item.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.never)
                .scrollPosition(id: $pageID)
                .scrollDisabled(items.count < 2)
            }
            .clipped()
            .overlay { heartBurst }
            .overlay(alignment: .topTrailing) {
                if items.count > 1 {
                    Text("\(currentIndex + 1)/\(items.count)")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.6), in: .capsule)
                        .padding(12)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if current?.videoURL != nil {
                    Button { isMuted.toggle() } label: {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color(white: 0.15).opacity(0.8)))
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                }
            }
            .overlay {
                if isHovering && items.count > 1 {
                    HStack {
                        pageButton("chevron.left", enabled: currentIndex > 0) { go(to: currentIndex - 1) }
                        Spacer()
                        pageButton("chevron.right", enabled: currentIndex < items.count - 1) { go(to: currentIndex + 1) }
                    }
                    .padding(.horizontal, 10)
                    .transition(.opacity)
                }
            }
            .contentShape(.rect)
            .onTapGesture(count: 2) {
                onDoubleTap()
                triggerHeartBurst()
            }
            .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering } }
            .onChange(of: pageID) { _, newValue in
                if let newValue, let index = items.firstIndex(where: { $0.id == newValue }) {
                    currentIndex = index
                    ImagePipeline.shared.prefetch([items[safe: index + 1]?.imageURL], maxPixelSize: 1080)
                }
            }
    }

    private func go(to index: Int) {
        guard let target = items[safe: index] else { return }
        withAnimation(.snappy(duration: 0.3)) { pageID = target.id }
    }

    private func pageButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.black.opacity(0.75))
                .frame(width: 26, height: 26)
                .background(Circle().fill(.white.opacity(0.85)))
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.88))
        .opacity(enabled ? 1 : 0)
        .disabled(!enabled)
    }

    @ViewBuilder
    private var heartBurst: some View {
        if showHeartBurst {
            Image(systemName: "heart.fill")
                .font(.system(size: 92))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 14, y: 4)
                .scaleEffect(heartScale)
                .opacity(heartOpacity)
                .allowsHitTesting(false)
        }
    }

    private func triggerHeartBurst() {
        showHeartBurst = true
        heartScale = 0.2
        heartOpacity = 1.0
        withAnimation(.spring(duration: 0.35, bounce: 0.5)) {
            heartScale = 1.0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(.easeIn(duration: 0.2)) {
                heartOpacity = 0
                heartScale = 0.6
            }
            try? await Task.sleep(for: .milliseconds(220))
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
    @State private var isOnScreen = false

    var body: some View {
        let isPhone = store.layoutMode == .phone

        VStack(alignment: .leading, spacing: 10) {
            header
                .padding(.horizontal, 14)

            MediaPager(items: post.items, currentIndex: $currentSlide, isVisible: isOnScreen) {
                if !post.hasLiked { store.toggleLike(post) }
            }
            .onScrollVisibilityChange(threshold: 0.6) { isOnScreen = $0 }
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
                            .fill(active ? Color.igBlue : Color.secondary.opacity(0.32))
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
                        .foregroundStyle(post.hasLiked ? Color.igLike : Color.primary)
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
                            if post.id == store.feed.dropLast(3).last?.id || post.id == store.feed.last?.id {
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
    @State private var query = ""
    @State private var results: AppStore.SearchResults?
    @State private var isSearching = false
    @State private var width: CGFloat = 0

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Group {
            if trimmedQuery.isEmpty {
                mosaic
            } else {
                searchResults
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Ara")
        .task(id: trimmedQuery) {
            guard !trimmedQuery.isEmpty else {
                results = nil
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            isSearching = true
            let found = await store.search(trimmedQuery)
            guard !Task.isCancelled else { return }
            results = found
            isSearching = false
        }
    }

    // MARK: Mosaic (groups of five: a 2x2 block and one tall tile, alternating sides)

    private var mosaic: some View {
        ScrollView {
            let spacing: CGFloat = 2
            let side = max(0, (width - spacing * 2) / 3)
            let groups = stride(from: 0, to: store.explore.count, by: 5).map { Array(store.explore[$0..<min($0 + 5, store.explore.count)]) }
            LazyVStack(spacing: spacing) {
                ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                    mosaicGroup(group, tallOnRight: index.isMultiple(of: 2), side: side, spacing: spacing)
                }
            }
            .frame(maxWidth: store.layoutMode == .phone ? .infinity : 935)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .frame(maxWidth: .infinity)
        }
        .overlay {
            LoadStateView(phase: store.explorePhase, isEmpty: store.explore.isEmpty, emptyTitle: "Keşfet boş", emptySymbol: "magnifyingglass") {
                Task { await store.refresh(.explore) }
            }
        }
    }

    @ViewBuilder
    private func mosaicGroup(_ group: [IGPost], tallOnRight: Bool, side: CGFloat, spacing: CGFloat) -> some View {
        if group.count < 5 {
            HStack(spacing: spacing) {
                ForEach(group) { tile($0, width: side, height: side) }
                Spacer(minLength: 0)
            }
        } else {
            let tall = group.first(where: \.isVideo) ?? group[4]
            let small = group.filter { $0.id != tall.id }
            HStack(spacing: spacing) {
                if !tallOnRight { tile(tall, width: side, height: side * 2 + spacing) }
                VStack(spacing: spacing) {
                    HStack(spacing: spacing) { tile(small[0], width: side, height: side); tile(small[1], width: side, height: side) }
                    HStack(spacing: spacing) { tile(small[2], width: side, height: side); tile(small[3], width: side, height: side) }
                }
                if tallOnRight { tile(tall, width: side, height: side * 2 + spacing) }
            }
        }
    }

    private func tile(_ post: IGPost, width: CGFloat, height: CGFloat) -> some View {
        MediaGridTile(post: post, aspectRatio: width / max(height, 1)) { store.detailPost = post }
            .frame(width: width, height: height)
    }

    // MARK: Search

    private var searchResults: some View {
        List {
            if let results {
                ForEach(results.users) { user in
                    Button { store.openProfile(of: user) } label: {
                        HStack(spacing: 12) {
                            AvatarView(url: user.avatarURL, size: 44)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text(user.username).font(.system(size: 13.5, weight: .semibold))
                                    if user.isVerified { VerifiedBadge(size: 11) }
                                }
                                let detail = [user.fullName, user.isFollowing == true ? "Takip ediliyor" : nil]
                                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " • ")
                                if !detail.isEmpty {
                                    Text(detail).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                }
                ForEach(results.hashtags, id: \.name) { tag in
                    Button {
                        NSWorkspace.shared.open(URL(string: "https://www.instagram.com/explore/tags/\(tag.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag.name)/")!)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "number")
                                .font(.system(size: 18))
                                .frame(width: 44, height: 44)
                                .overlay(Circle().strokeBorder(Color.igSeparator, lineWidth: 1))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("#\(tag.name)").font(.system(size: 13.5, weight: .semibold))
                                if tag.mediaCount > 0 {
                                    Text("\(tag.mediaCount.igCompact) gönderi").font(.system(size: 13)).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if isSearching && results == nil {
                ProgressView()
            } else if let results, results.users.isEmpty && results.hashtags.isEmpty {
                ContentUnavailableView.search(text: trimmedQuery)
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
    @State private var activeID: String?
    @AppStorage("reelsMuted") private var isMuted = false

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(store.reels) { reel in
                    ReelPage(reel: reel, store: store, isActive: reel.id == (activeID ?? store.reels.first?.id), isMuted: $isMuted)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(reel.id)
                        .onAppear {
                            if reel.id == store.reels.dropLast(2).last?.id {
                                Task { await store.loadMoreReels() }
                            }
                        }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.never)
        .scrollPosition(id: $activeID)
        .background(store.layoutMode == .phone ? Color.black : Color.clear)
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
    let isActive: Bool
    @Binding var isMuted: Bool

    @State private var isPaused = false
    @State private var flashSymbol: String?

    var body: some View {
        GeometryReader { geo in
            let immersive = store.layoutMode == .phone || geo.size.width < 560
            if immersive {
                video
                    .overlay(alignment: .bottom) { overlayChrome(light: true) }
            } else {
                let height = geo.size.height - 32
                let width = (height * 9 / 16).rounded()
                HStack(alignment: .bottom, spacing: 18) {
                    video
                        .frame(width: width, height: height)
                        .clipShape(.rect(cornerRadius: 8, style: .continuous))
                        .overlay(alignment: .bottomLeading) { caption.padding(16) }
                    actions(light: false)
                        .padding(.bottom, 8)
                }
                .padding(.leading, 64)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var video: some View {
        ZStack {
            if let url = reel.items.first?.videoURL {
                LoopingVideo(url: url, isPlaying: isActive && !isPaused, isMuted: isMuted)
            } else {
                RemoteImage(url: reel.items.first?.imageURL)
            }
            if let flashSymbol {
                Image(systemName: flashSymbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 68, height: 68)
                    .background(Circle().fill(.black.opacity(0.45)))
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .contentShape(.rect)
        .onTapGesture(count: 2) {
            if !reel.hasLiked { store.toggleLike(reel) }
            flash("heart.fill")
        }
        .onTapGesture {
            isMuted.toggle()
            flash(isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
        }
        .onLongPressGesture(minimumDuration: 0.25) {} onPressingChanged: { pressing in
            isPaused = pressing
        }
        .onChange(of: isActive) { _, active in if active { isPaused = false } }
    }

    private func flash(_ symbol: String) {
        withAnimation(.spring(duration: 0.25, bounce: 0.3)) { flashSymbol = symbol }
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.easeOut(duration: 0.2)) { flashSymbol = nil }
        }
    }

    private func overlayChrome(light: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            caption
            Spacer(minLength: 0)
            actions(light: true)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 20)
        .padding(.top, 120)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        )
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { store.openProfile(of: reel.user) } label: {
                HStack(spacing: 8) {
                    AvatarView(url: reel.user.avatarURL, size: 30)
                    Text(reel.user.username)
                        .font(.system(size: 13.5, weight: .semibold))
                    if reel.user.isVerified { VerifiedBadge(size: 11) }
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
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
    }

    private func actions(light: Bool) -> some View {
        VStack(spacing: 18) {
            actionButton(reel.hasLiked ? "heart.fill" : "heart", count: reel.likeCount, tint: reel.hasLiked ? .igLike : nil, light: light) {
                withAnimation(.spring(duration: 0.3, bounce: 0.5)) { store.toggleLike(reel) }
            }
            .symbolEffect(.bounce, value: reel.hasLiked)
            actionButton("bubble.right", count: reel.commentCount, light: light) { store.detailPost = reel }
            actionButton("paperplane", count: nil, light: light) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("https://www.instagram.com/reel/\(reel.code)/", forType: .string)
                flash("link")
            }
            actionButton(reel.hasSaved ? "bookmark.fill" : "bookmark", count: nil, light: light) {
                withAnimation(.spring(duration: 0.28, bounce: 0.4)) { store.toggleSave(reel) }
            }
            .symbolEffect(.bounce, value: reel.hasSaved)
            Button {
                NSWorkspace.shared.open(URL(string: "https://www.instagram.com/reel/\(reel.code)/")!)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 40, height: 24)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(light ? Color.white : Color.primary)
            .help("Tarayıcıda Aç")
        }
        .shadow(color: light ? .black.opacity(0.3) : .clear, radius: 3, y: 1)
    }

    private func actionButton(_ symbol: String, count: Int?, tint: Color? = nil, light: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 24))
                    .foregroundStyle(tint ?? (light ? Color.white : Color.primary))
                if let count {
                    Text(count.igCompact)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(light ? Color.white : Color.primary)
                }
            }
            .frame(width: 44)
            .contentShape(.rect)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.85))
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
