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
                ForEach(store.stories) { tray in
                    Button {
                        store.openStory(tray)
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

// MARK: - Activity

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

// MARK: - Direct Messages & Notes

struct MessagesView: View {
    @Bindable var store: AppStore
    @State private var phoneOpenThread: IGDirectThread?

    var body: some View {
        Group {
            if store.layoutMode == .phone {
                NavigationStack {
                    threadList(isPhone: true)
                        .navigationDestination(item: $phoneOpenThread) { thread in
                            DirectConversationView(threadID: thread.id, store: store)
                        }
                }
            } else {
                HStack(spacing: 0) {
                    threadList(isPhone: false)
                        .frame(width: 310)
                    Divider()
                    if let thread = store.selectedThread {
                        DirectConversationView(threadID: thread.id, store: store)
                            .id(thread.id)
                    } else {
                        ContentUnavailableView(
                            "Sohbet Seçin",
                            systemImage: "paperplane",
                            description: Text("Mesajları görüntülemek veya yanıtlamak için soldaki listeden bir kişi seçin.")
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

    private func threadList(isPhone: Bool) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !store.notes.isEmpty {
                    NotesBar(store: store)
                    Divider()
                }

                ForEach(store.directThreads) { thread in
                    let isSelected = !isPhone && store.selectedThread?.id == thread.id
                    Button {
                        store.selectThread(thread)
                        if isPhone { phoneOpenThread = thread }
                    } label: {
                        HStack(spacing: 12) {
                            AvatarView(url: thread.users.first?.avatarURL, size: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 4) {
                                    Text(thread.title)
                                        .font(.subheadline.weight(thread.isUnread ? .bold : .semibold))
                                        .lineLimit(1)
                                    if thread.isPinned {
                                        Image(systemName: "pin.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(thread.lastActivityAt, format: .relative(presentation: .named))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text(thread.snippet.isEmpty ? "Mesajları görüntüle" : thread.snippet)
                                    .font(.caption)
                                    .foregroundStyle(thread.isUnread ? .primary : .secondary)
                                    .lineLimit(1)
                            }
                            if thread.isUnread {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(.rect)
                        .background(isSelected ? Color.primary.opacity(0.08) : Color.clear)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
    }
}

struct NotesBar: View {
    @Bindable var store: AppStore

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .bottom, spacing: 14) {
                ForEach(store.notes) { note in
                    Button {
                        store.openProfile(of: note.user)
                    } label: {
                        VStack(spacing: 4) {
                            VStack(spacing: 2) {
                                if !note.text.isEmpty {
                                    Text(note.text)
                                        .font(.caption2)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                }
                                if let music = note.musicTitle, !music.isEmpty {
                                    HStack(spacing: 3) {
                                        Image(systemName: "music.note")
                                            .font(.system(size: 8, weight: .bold))
                                        Text(music)
                                            .font(.system(size: 9, weight: .medium))
                                            .lineLimit(1)
                                    }
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .frame(maxWidth: 92)
                            .background(.quaternary.opacity(0.65), in: .rect(cornerRadius: 12))

                            AvatarView(url: note.user.avatarURL, size: 46)

                            Text(note.user.id == store.viewerID ? "Notun" : note.user.username)
                                .font(.caption2)
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
    }
}

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
                Divider()
                messagesList(thread)
                Divider()
                composer(thread)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func conversationHeader(_ thread: IGDirectThread) -> some View {
        HStack(spacing: 10) {
            AvatarView(url: thread.users.first?.avatarURL, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(thread.title).font(.subheadline.weight(.semibold))
                if let username = thread.users.first?.username {
                    Text("@\(username)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let user = thread.users.first {
                Button("Profili Aç") { store.openProfile(of: user) }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func messagesList(_ thread: IGDirectThread) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if thread.messages.isEmpty {
                        Text("Mesaj geçmişi yükleniyor veya henüz mesaj yok.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 32)
                    }
                    ForEach(thread.messages) { message in
                        HStack(alignment: .bottom, spacing: 8) {
                            if message.isFromViewer {
                                Spacer(minLength: 48)
                            } else {
                                AvatarView(url: message.senderAvatarURL ?? thread.users.first?.avatarURL, size: 24)
                            }

                            VStack(alignment: message.isFromViewer ? .trailing : .leading, spacing: 3) {
                                Text(message.text)
                                    .font(.subheadline)
                                    .foregroundStyle(message.isFromViewer ? Color.white : Color.primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        message.isFromViewer ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                                        in: .rect(cornerRadius: 16)
                                    )

                                Text(message.timestamp, format: .dateTime.hour().minute())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            if !message.isFromViewer {
                                Spacer(minLength: 48)
                            }
                        }
                        .id(message.id)
                    }
                }
                .padding(16)
            }
            .onChange(of: thread.messages.count, initial: true) { _, _ in
                if let lastID = thread.messages.last?.id {
                    withAnimation(.snappy(duration: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func composer(_ thread: IGDirectThread) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if sendFailed {
                Text("Mesaj gönderilemedi. Yeniden deneyin.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack(spacing: 8) {
                TextField("Mesaj yaz…", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { send(in: thread) }
                Button("Gönder") { send(in: thread) }
                    .buttonStyle(.glassProminent)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isSendingDirectMessage)
            }
        }
        .padding(12)
    }

    private func send(in thread: IGDirectThread) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !store.isSendingDirectMessage else { return }
        sendFailed = false
        Task {
            let ok = await store.sendDirectMessage(text: text, in: thread)
            if ok {
                draft = ""
            } else {
                sendFailed = true
            }
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
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 20) {
                            AvatarView(url: user.avatarURL, size: 84)
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 22) {
                                    stat(user.mediaCount ?? store.profilePosts.count, "gönderi")
                                    stat(user.followerCount, "takipçi")
                                    stat(user.followingCount, "takip")
                                }
                                if user.id != store.viewerID, let isFollowing = user.isFollowing {
                                    Button(isFollowing ? "Takipten Çık" : "Takip Et") {
                                        store.toggleFollow(user)
                                    }
                                    .buttonStyle(.glassProminent)
                                    .controlSize(.small)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
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
                            if let link = user.externalURL {
                                Link(destination: link) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "link")
                                        Text(link.host ?? link.absoluteString)
                                            .lineLimit(1)
                                    }
                                    .font(.caption.weight(.medium))
                                }
                            }
                        }

                        if !store.profileHighlights.isEmpty {
                            ScrollView(.horizontal) {
                                LazyHStack(spacing: 14) {
                                    ForEach(store.profileHighlights) { highlight in
                                        Button {
                                            store.openStory(highlight)
                                        } label: {
                                            VStack(spacing: 5) {
                                                AvatarView(url: highlight.coverURL ?? user.avatarURL, size: 52, ring: .seen)
                                                Text(highlight.title ?? "Öne Çıkan")
                                                    .font(.caption2)
                                                    .lineLimit(1)
                                                    .frame(width: 64)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .scrollIndicators(.hidden)
                        }
                    }
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    Divider()

                    if store.profilePosts.isEmpty && user.isPrivate && user.isFollowing != true && user.id != store.viewerID {
                        ContentUnavailableView(
                            "Bu Hesap Gizli",
                            systemImage: "lock.fill",
                            description: Text("Fotoğraf ve videolarını görmek için bu hesabı takip edin.")
                        )
                        .padding(.top, 24)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 2)], spacing: 2) {
                            ForEach(store.profilePosts) { post in
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
