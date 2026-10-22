import SwiftUI
import AppKit
import AVKit

// MARK: - Messages (Apple Messages layout, Instagram data)

struct MessagesView: View {
    @Bindable var store: AppStore
    @State private var phoneOpenThread: IGDirectThread?
    @State private var searchText = ""

    private var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    private var filteredThreads: [IGDirectThread] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.directThreads }
        return store.directThreads.filter {
            $0.title.lowercased().contains(q)
                || $0.snippet.lowercased().contains(q)
                || $0.users.contains(where: { $0.username.lowercased().contains(q) || $0.fullName.lowercased().contains(q) })
        }
    }

    var body: some View {
        Group {
            if store.layoutMode == .phone {
                NavigationStack {
                    inbox(isPhone: true)
                        .navigationDestination(item: $phoneOpenThread) { thread in
                            DirectConversationView(threadID: thread.id, store: store)
                        }
                }
            } else {
                HStack(spacing: 0) {
                    inbox(isPhone: false)
                        .frame(width: 320)
                    Divider()
                    if let thread = store.selectedThread {
                        DirectConversationView(threadID: thread.id, store: store)
                            .id(thread.id)
                    } else {
                        ContentUnavailableView("Sohbet Seçin", systemImage: "message")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .overlay {
            LoadStateView(phase: store.directPhase, isEmpty: store.directThreads.isEmpty && store.notes.isEmpty, emptyTitle: "Mesaj kutusu boş", emptySymbol: "message") {
                Task { await store.refresh(.direct) }
            }
        }
        .onAppear(perform: consumePendingSearch)
        .onChange(of: store.pendingDirectSearch) { _, _ in consumePendingSearch() }
    }

    private func consumePendingSearch() {
        guard let pending = store.pendingDirectSearch else { return }
        searchText = pending
        store.pendingDirectSearch = nil
    }

    private func open(_ thread: IGDirectThread, isPhone: Bool) {
        store.selectThread(thread)
        if isPhone { phoneOpenThread = thread }
    }

    private func inbox(isPhone: Bool) -> some View {
        let threads = filteredThreads
        let pinned = isSearching ? [] : threads.filter(\.isPinned)
        let rows = isSearching ? threads : threads.filter { !$0.isPinned }
        let selectedID = isPhone ? nil : store.selectedThread?.id

        return VStack(spacing: 0) {
            MessagesSearchField(text: $searchText)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if !store.notes.isEmpty && !isSearching {
                        NotesBar(store: store)
                    }

                    if !pinned.isEmpty {
                        PinnedConversationsGrid(threads: pinned, selectedID: selectedID) { open($0, isPhone: isPhone) }
                            .padding(.bottom, 6)
                    }

                    ForEach(Array(rows.enumerated()), id: \.element.id) { offset, thread in
                        let nextIsSelected = rows[safe: offset + 1]?.id == selectedID
                        InboxThreadRow(
                            thread: thread,
                            isSelected: thread.id == selectedID,
                            showsSeparator: thread.id != selectedID && !nextIsSelected && offset < rows.count - 1
                        ) {
                            open(thread, isPhone: isPhone)
                        }
                        .contextMenu {
                            Button(thread.isUnread ? "Okundu Olarak İşaretle" : "Okunmadı Olarak İşaretle") {
                                store.markThreadRead(thread, thread.isUnread)
                            }
                            if let user = thread.users.first, !thread.isGroup {
                                Button("Profili Gör") { store.openProfile(of: user) }
                            }
                        }
                    }

                    if isSearching && rows.isEmpty {
                        Text("Sonuç yok")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.top, 30)
                    }
                }
                .padding(.bottom, isPhone ? 70 : 8)
            }
        }
    }
}

// MARK: Inbox pieces

private struct MessagesSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Ara", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.7)))
        .animation(.easeOut(duration: 0.15), value: text.isEmpty)
    }
}

/// A person's photo, or two overlapping photos for a group, like Apple Messages.
struct ConversationAvatar: View {
    let thread: IGDirectThread
    var size: CGFloat = 44

    var body: some View {
        if thread.isGroup, thread.users.count > 1 {
            let small = size * 0.68
            ZStack {
                AvatarView(url: thread.users[1].avatarURL, size: small)
                    .offset(x: size * 0.16, y: -size * 0.16)
                AvatarView(url: thread.users[0].avatarURL, size: small)
                    .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                    .offset(x: -size * 0.16, y: size * 0.16)
            }
            .frame(width: size, height: size)
        } else {
            AvatarView(url: thread.users.first?.avatarURL, size: size)
        }
    }
}

private struct PinnedConversationsGrid: View {
    let threads: [IGDirectThread]
    let selectedID: String?
    let open: (IGDirectThread) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 14) {
            ForEach(threads) { thread in
                Button { open(thread) } label: {
                    VStack(spacing: 6) {
                        ConversationAvatar(thread: thread, size: 62)
                            .overlay(alignment: .topLeading) {
                                if thread.isUnread {
                                    Circle()
                                        .fill(Color.messagesBlue)
                                        .frame(width: 12, height: 12)
                                        .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                                }
                            }
                            .overlay(alignment: .top) {
                                if thread.isUnread, !thread.snippet.isEmpty {
                                    Text(thread.snippet)
                                        .font(.system(size: 10.5))
                                        .lineLimit(2)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 4)
                                        .frame(maxWidth: 92)
                                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.messagesGray))
                                        .fixedSize(horizontal: false, vertical: true)
                                        .offset(y: -26)
                                }
                            }
                        Text(thread.title)
                            .font(.system(size: 11.5, weight: thread.isUnread ? .semibold : .regular))
                            .foregroundStyle(thread.id == selectedID ? Color.white : Color.primary)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(thread.id == selectedID ? Color.accentColor : .clear))
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, threads.contains(where: { $0.isUnread }) ? 30 : 10)
    }
}

private struct InboxThreadRow: View {
    let thread: IGDirectThread
    let isSelected: Bool
    let showsSeparator: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Circle()
                    .fill(thread.isUnread ? Color.messagesBlue : .clear)
                    .frame(width: 9, height: 9)
                    .frame(width: 20)

                ConversationAvatar(thread: thread, size: 42)
                    .padding(.trailing, 10)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(thread.title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .lineLimit(1)
                        if !thread.isGroup, thread.users.first?.isVerified == true {
                            VerifiedBadge(size: 10)
                        }
                        Spacer(minLength: 6)
                        Text(thread.lastActivityAt.messagesListStamp)
                            .font(.system(size: 12))
                            .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                    }
                    Text(thread.snippet.isEmpty ? " " : thread.snippet)
                        .font(.system(size: 13))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                }
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.trailing, 10)
            }
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.accentColor : .clear)
            )
            .overlay(alignment: .bottom) {
                if showsSeparator {
                    Rectangle()
                        .fill(Color.igSeparator)
                        .frame(height: 0.5)
                        .padding(.leading, 72)
                }
            }
            .padding(.horizontal, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Instagram's Notes row: a thought bubble above each avatar.
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
                            AvatarView(url: note.user.avatarURL, size: 62)
                                .overlay(alignment: .top) { bubble(note).offset(y: -34) }
                                .padding(.top, 40)
                            Text(note.user.id == store.viewerID ? "Notun" : note.user.username)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(width: 74)
                        }
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func bubble(_ note: IGNote) -> some View {
        let fill = Color(light: 0xFFFFFF, dark: 0x262626)
        return VStack(alignment: .leading, spacing: 1) {
            VStack(spacing: 2) {
                if let music = note.musicTitle, !music.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "waveform")
                            .font(.system(size: 8, weight: .bold))
                        Text(music)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                    }
                    if let artist = note.musicArtist {
                        Text(artist)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if !note.text.isEmpty {
                    Text(note.text)
                        .font(.system(size: 11))
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(minWidth: 40, maxWidth: 92)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill).shadow(color: .black.opacity(0.14), radius: 4, y: 1))
            .fixedSize(horizontal: false, vertical: true)

            Circle().fill(fill).frame(width: 7, height: 7).shadow(color: .black.opacity(0.1), radius: 1, y: 0.5).padding(.leading, 14)
            Circle().fill(fill).frame(width: 4, height: 4).padding(.leading, 11)
        }
    }
}

// MARK: - Conversation

struct DirectConversationView: View {
    let threadID: String
    @Bindable var store: AppStore
    @State private var draft = ""
    @State private var replyingTo: IGDirectMessage?
    @State private var preview: IGMediaItem?
    @FocusState private var composerFocused: Bool

    private var thread: IGDirectThread? {
        store.directThreads.first(where: { $0.id == threadID })
    }

    var body: some View {
        if let thread {
            transcript(thread)
                .safeAreaInset(edge: .top, spacing: 0) { header(thread) }
                .safeAreaInset(edge: .bottom, spacing: 0) { composer(thread) }
                .overlay(alignment: .top) { notice }
                .overlay { mediaPreview }
                .onAppear {
                    composerFocused = true
                    store.markThreadRead(thread)
                }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Header (iOS Messages: centred photo with the name in a capsule underneath)

    private func header(_ thread: IGDirectThread) -> some View {
        ZStack {
            Button {
                if !thread.isGroup, let user = thread.users.first { store.openProfile(of: user) }
            } label: {
                VStack(spacing: 3) {
                    ConversationAvatar(thread: thread, size: 38)
                    HStack(spacing: 2) {
                        Text(thread.title)
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96))

            if !thread.isGroup, let user = thread.users.first {
                HStack {
                    Spacer()
                    Button { store.openProfile(of: user) } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 17))
                            .foregroundStyle(Color.messagesBlue)
                            .frame(width: 30, height: 30)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help("Profil")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.igSeparator).frame(height: 0.5) }
    }

    // MARK: Transcript

    private func transcript(_ thread: IGDirectThread) -> some View {
        let messages = thread.messages
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ConversationIntro(thread: thread, store: store)

                    if messages.isEmpty {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.top, 10)
                    }

                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        let layout = MessageLayout(messages: messages, index: index, isGroup: thread.isGroup)
                        VStack(spacing: 0) {
                            if layout.showsTimestamp {
                                Text(message.timestamp.messagesTranscriptStamp)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 14)
                                    .padding(.bottom, 6)
                            }
                            MessageRow(
                                message: message,
                                layout: layout,
                                avatarURL: message.senderAvatarURL ?? thread.users.first(where: { $0.username == message.senderUsername })?.avatarURL,
                                peerName: thread.isGroup ? nil : thread.users.first?.username,
                                actions: MessageActions(
                                    react: { store.react($0, to: message, in: thread) },
                                    reply: {
                                        withAnimation(.snappy(duration: 0.2)) { replyingTo = message }
                                        composerFocused = true
                                    },
                                    retry: { store.retryDirectMessage(message, in: thread) },
                                    openMedia: { media in withAnimation(.easeOut(duration: 0.2)) { preview = media } },
                                    openLink: { store.openWeb($0) }
                                )
                            )
                        }
                        .id(message.id)
                        .transition(
                            message.isFromViewer
                                ? .asymmetric(insertion: .move(edge: .bottom).combined(with: .scale(scale: 0.6, anchor: .bottomTrailing)).combined(with: .opacity), removal: .opacity)
                                : .asymmetric(insertion: .scale(scale: 0.85, anchor: .bottomLeading).combined(with: .opacity), removal: .opacity)
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .onChange(of: messages.last?.id) { _, last in
                guard let last else { return }
                withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    // MARK: Composer (iOS 26 Messages: round + button and a glass field)

    private func composer(_ thread: IGDirectThread) -> some View {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return VStack(spacing: 6) {
            if let replyingTo {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(Color.messagesBlue)
                        .frame(width: 2.5)
                        .clipShape(.capsule)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(replyingTo.isFromViewer ? "Kendine yanıt veriyorsun" : "\(replyingTo.senderUsername ?? thread.title) adlı kişiye yanıt veriyorsun")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text(replyingTo.text.isEmpty ? replyingTo.kind.label : replyingTo.text)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { self.replyingTo = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: 32)
                .padding(.horizontal, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button("❤️  Kalp Gönder") { store.sendDirectMessage(text: "❤️", in: thread) }
                    Button("👍  Beğen") { store.sendDirectMessage(text: "👍", in: thread) }
                    Button("😂") { store.sendDirectMessage(text: "😂", in: thread) }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .contentShape(.circle)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .glassEffect(.regular.interactive(), in: .circle)

                HStack(alignment: .bottom, spacing: 4) {
                    TextField(replyingTo == nil ? "Mesaj" : "Yanıt", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .lineLimit(1...6)
                        .focused($composerFocused)
                        .onSubmit { send(in: thread) }
                        .padding(.vertical, 8)

                    if hasText {
                        Button { send(in: thread) } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 26))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.messagesBlue)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 4)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                .padding(.leading, 14)
                .padding(.trailing, hasText ? 4 : 14)
                .frame(minHeight: 34)
                .glassEffect(.regular, in: .rect(cornerRadius: 17, style: .continuous))
                .animation(.spring(duration: 0.25, bounce: 0.3), value: hasText)
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 6)
        .padding(.bottom, 10)
        .onKeyPress(.escape) {
            guard replyingTo != nil else { return .ignored }
            withAnimation(.snappy(duration: 0.2)) { replyingTo = nil }
            return .handled
        }
    }

    private func send(in thread: IGDirectThread) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        if let target = replyingTo {
            withAnimation(.snappy(duration: 0.2)) { replyingTo = nil }
            store.sendReply(text: text, to: target, in: thread)
        } else {
            store.sendDirectMessage(text: text, in: thread)
        }
    }

    // MARK: Overlays

    @ViewBuilder
    private var notice: some View {
        if let message = store.directNotice {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.system(size: 12.5, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .glassEffect(.regular, in: .capsule)
                .padding(.top, 70)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { store.directNotice = nil }
                }
        }
    }

    @ViewBuilder
    private var mediaPreview: some View {
        if let preview {
            ZStack {
                Color.black.opacity(0.92)
                    .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { self.preview = nil } }
                Group {
                    if let video = preview.videoURL {
                        LoopingVideo(url: video, isPlaying: true, isMuted: false, fillsFrame: false)
                    } else {
                        CachedImage(url: preview.imageURL, maxPixelSize: 2048, contentMode: .fit) { _ in ProgressView().tint(.white) }
                    }
                }
                .padding(24)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) {
                Button { withAnimation(.easeOut(duration: 0.2)) { self.preview = nil } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .padding(14)
            }
            .transition(.opacity)
        }
    }
}

/// Instagram's contact card at the top of a conversation.
private struct ConversationIntro: View {
    let thread: IGDirectThread
    @Bindable var store: AppStore

    var body: some View {
        VStack(spacing: 4) {
            ConversationAvatar(thread: thread, size: 88)
                .padding(.bottom, 6)
            Text(thread.title)
                .font(.system(size: 17, weight: .bold))
                .multilineTextAlignment(.center)
            if !thread.isGroup, let peer = thread.users.first {
                Text("\(peer.username) · Instagram")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Button("Profili gör") { store.openProfile(of: peer) }
                    .buttonStyle(IGButtonStyle(fillsWidth: false))
                    .padding(.top, 8)
            } else {
                Text("\(thread.users.count + 1) kişi")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }
}

// MARK: - Bubbles

/// How one message sits among its neighbours: Apple Messages groups consecutive messages from the
/// same sender, with a tail only on the last, and starts a new group after a timestamp.
struct MessageLayout {
    let showsTimestamp: Bool
    let isFirstInGroup: Bool
    let isLastInGroup: Bool
    let showsSenderName: Bool
    let showsAvatarColumn: Bool
    let isLastFromViewer: Bool

    init(messages: [IGDirectMessage], index: Int, isGroup: Bool) {
        let message = messages[index]
        let previous = messages[safe: index - 1]
        let next = messages[safe: index + 1]
        let gap: TimeInterval = 60 * 60

        showsTimestamp = previous.map { message.timestamp.timeIntervalSince($0.timestamp) > gap } ?? true
        let nextStartsNewSection = next.map { $0.timestamp.timeIntervalSince(message.timestamp) > gap } ?? true
        isFirstInGroup = showsTimestamp || previous?.senderFBID != message.senderFBID || message.replyTo != nil
        isLastInGroup = nextStartsNewSection || next?.senderFBID != message.senderFBID || next?.replyTo != nil
        showsSenderName = isGroup && !message.isFromViewer && isFirstInGroup
        showsAvatarColumn = isGroup && !message.isFromViewer
        isLastFromViewer = message.isFromViewer && !messages[(index + 1)...].contains(where: \.isFromViewer)
    }
}

struct MessageActions {
    let react: (String) -> Void
    let reply: () -> Void
    let retry: () -> Void
    let openMedia: (IGMediaItem) -> Void
    let openLink: (URL) -> Void
}

/// Instagram's quick reactions.
let quickReactions = ["❤️", "😂", "😮", "😢", "😡", "👍"]

private struct MessageRow: View {
    let message: IGDirectMessage
    let layout: MessageLayout
    let avatarURL: URL?
    let peerName: String?
    let actions: MessageActions

    @State private var isHovered = false
    @State private var showsReactions = false

    private var outgoing: Bool { message.isFromViewer }
    private var isEmojiOnly: Bool { message.media == nil && message.share == nil && message.text.isBigEmoji }
    private var canAct: Bool { message.delivery == .sent && !message.id.hasPrefix("local-") }

    var body: some View {
        VStack(alignment: outgoing ? .trailing : .leading, spacing: 2) {
            if layout.showsSenderName, let name = message.senderUsername {
                Text(name)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 40)
            }

            if let quote = message.replyTo {
                replyQuote(quote)
            } else if let caption = kindCaption {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, layout.showsAvatarColumn ? 40 : 6)
            }

            HStack(alignment: .bottom, spacing: 6) {
                if outgoing {
                    Spacer(minLength: 40)
                    hoverActions
                }

                if layout.showsAvatarColumn {
                    Group {
                        if layout.isLastInGroup { AvatarView(url: avatarURL, size: 26) } else { Color.clear }
                    }
                    .frame(width: 26, height: 26)
                }

                if message.delivery == .failed {
                    Button(action: actions.retry) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Tekrar gönder")
                }

                content
                    .overlay(alignment: outgoing ? .bottomLeading : .bottomTrailing) { reactionBadge }
                    .opacity(message.delivery == .sending ? 0.7 : 1)
                    .onTapGesture(count: 2) { if canAct { actions.react("❤️") } }
                    .popover(isPresented: $showsReactions, arrowEdge: .top) { reactionPicker }
                    .contextMenu { contextMenu }
                    .help(message.timestamp.formatted(date: .abbreviated, time: .shortened))

                if !outgoing {
                    hoverActions
                    Spacer(minLength: 40)
                }
            }

            if outgoing && message.delivery != .sent && (layout.isLastFromViewer || message.delivery == .failed) {
                Text(message.delivery == .failed ? "Gönderilmedi" : "Gönderiliyor…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(message.delivery == .failed ? Color.red : Color.secondary)
                    .padding(.trailing, 4)
                    .transition(.opacity)
            }
        }
        .padding(.top, layout.isFirstInGroup ? 8 : 2)
        .padding(.bottom, message.reactions.isEmpty ? 0 : 14)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering } }
    }

    /// "Reels gönderdin", "Bir gönderi paylaştı"… Instagram labels everything that is not plain text.
    private var kindCaption: String? {
        let who = outgoing ? "" : (peerName.map { "\($0) " } ?? "")
        switch message.kind {
        case .reel: return outgoing ? "Bir Reels videosu gönderdin" : "\(who)bir Reels videosu gönderdi"
        case .post: return outgoing ? "Bir gönderi paylaştın" : "\(who)bir gönderi paylaştı"
        case .story: return outgoing ? "Bir hikaye paylaştın" : "\(who)bir hikaye paylaştı"
        case .storyReply: return outgoing ? "Hikayesine yanıt verdin" : "\(who)hikayene yanıt verdi"
        case .video: return message.text.isEmpty ? (outgoing ? "Video gönderdin" : "\(who)video gönderdi") : nil
        default: return nil
        }
    }

    // MARK: Content by kind

    @ViewBuilder
    private var content: some View {
        VStack(alignment: outgoing ? .trailing : .leading, spacing: 3) {
            switch message.kind {
            case .reel, .post, .story:
                ShareCard(message: message, openMedia: actions.openMedia, openLink: actions.openLink)
            case .link where message.share != nil:
                ShareCard(message: message, openMedia: actions.openMedia, openLink: actions.openLink)
            case .voice:
                VoiceBubble(url: message.audioURL, outgoing: outgoing, hasTail: layout.isLastInGroup)
            case .sticker:
                if let media = message.media {
                    CachedImage(url: media.imageURL, maxPixelSize: 400, contentMode: .fit) { _ in Color.clear }
                        .frame(width: 120, height: 120)
                }
            default:
                if let media = message.media {
                    MessageMediaBubble(media: media) { actions.openMedia(media) }
                }
            }
            if !message.text.isEmpty && message.kind != .voice {
                if isEmojiOnly {
                    Text(message.text).font(.system(size: 44))
                } else {
                    textBubble
                }
            }
        }
    }

    private var textBubble: some View {
        let fill = outgoing ? Color.messagesBlue : Color.messagesGray
        return Text(message.text.linkified(tint: outgoing ? .white : .messagesBlue))
            .font(.system(size: 14))
            .foregroundStyle(outgoing ? Color.white : Color.primary)
            .tint(outgoing ? .white : .messagesBlue)
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(alignment: outgoing ? .bottomTrailing : .bottomLeading) {
                ZStack(alignment: outgoing ? .bottomTrailing : .bottomLeading) {
                    RoundedRectangle(cornerRadius: 17, style: .continuous).fill(fill)
                    if layout.isLastInGroup {
                        BubbleTail()
                            .fill(fill)
                            .frame(width: 11, height: 16)
                            .scaleEffect(x: outgoing ? 1 : -1, anchor: .center)
                            .offset(x: outgoing ? 5 : -5)
                    }
                }
            }
    }

    /// Instagram shows what a reply answers as a faded bubble above it.
    private func replyQuote(_ quote: IGDirectMessage.ReplyQuote) -> some View {
        VStack(alignment: outgoing ? .trailing : .leading, spacing: 2) {
            Label {
                Text(outgoing
                     ? (quote.isFromViewer ? "Kendine yanıt verdin" : "\(quote.senderUsername ?? peerName ?? "Kişi") adlı kişiye yanıt verdin")
                     : (quote.isFromViewer ? "Sana yanıt verdi" : "Yanıt verdi"))
            } icon: {
                Image(systemName: "arrowshape.turn.up.left.fill")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            Text(quote.text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Color.messagesGray, lineWidth: 1.5))
                .padding(.bottom, -6)
        }
        .padding(.horizontal, layout.showsAvatarColumn ? 40 : 4)
        .padding(.top, 2)
    }

    // MARK: Reactions and actions

    @ViewBuilder
    private var reactionBadge: some View {
        if !message.reactions.isEmpty {
            Text(message.reactions.prefix(3).joined())
                .font(.system(size: 12))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.messagesGray))
                .overlay(Capsule().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                .offset(x: outgoing ? -10 : 10, y: 14)
                .transition(.scale.combined(with: .opacity))
        }
    }

    private var hoverActions: some View {
        HStack(spacing: 2) {
            actionButton("face.smiling", help: "İfade bırak") { showsReactions = true }
            actionButton("arrowshape.turn.up.left", help: "Yanıtla", action: actions.reply)
        }
        .opacity(isHovered && canAct ? 1 : 0)
        .allowsHitTesting(isHovered && canAct)
        .padding(.bottom, 4)
    }

    private func actionButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var reactionPicker: some View {
        HStack(spacing: 2) {
            ForEach(quickReactions, id: \.self) { emoji in
                Button {
                    showsReactions = false
                    actions.react(emoji)
                } label: {
                    Text(emoji)
                        .font(.system(size: 24))
                        .frame(width: 38, height: 38)
                        .contentShape(.circle)
                }
                .buttonStyle(PressableButtonStyle(scale: 0.8))
            }
        }
        .padding(6)
    }

    @ViewBuilder
    private var contextMenu: some View {
        if canAct {
            ForEach(quickReactions, id: \.self) { emoji in
                Button("\(emoji)  İfade bırak") { actions.react(emoji) }
            }
            Divider()
            Button("Yanıtla", action: actions.reply)
        }
        if !message.text.isEmpty {
            Button("Kopyala") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.text, forType: .string)
            }
        }
        if let link = message.share?.url {
            Button("Bağlantıyı Aç") { actions.openLink(link) }
        }
        if message.delivery == .failed {
            Button("Tekrar Gönder", action: actions.retry)
        }
    }
}

/// The hooked tail Apple Messages draws on the last bubble of a group (drawn for an outgoing bubble; mirror it for incoming).
struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let edge = w - 5
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + edge, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.minX + w, y: rect.minY + h),
            control1: CGPoint(x: rect.minX + edge, y: rect.minY + h * 0.55),
            control2: CGPoint(x: rect.minX + w - 2, y: rect.minY + h - 1)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + h - 2),
            control: CGPoint(x: rect.minX + edge, y: rect.minY + h - 1.5)
        )
        path.closeSubpath()
        return path
    }
}

private struct MessageMediaBubble: View {
    let media: IGMediaItem
    let open: () -> Void

    var body: some View {
        let width: CGFloat = 220
        Button(action: open) {
            RemoteImage(url: media.thumbURL ?? media.imageURL, maxPixelSize: 640)
                .frame(width: width, height: width / max(media.aspectRatio, 0.56))
                .clipShape(.rect(cornerRadius: 17, style: .continuous))
                .overlay {
                    if media.videoURL != nil {
                        Image(systemName: "play.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .glassEffect(.regular, in: .circle)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        }
        .buttonStyle(PressableButtonStyle(scale: 0.97))
    }
}

/// A shared reel, post or story drawn the way Instagram does: owner header, preview and caption.
private struct ShareCard: View {
    let message: IGDirectMessage
    let openMedia: (IGMediaItem) -> Void
    let openLink: (URL) -> Void

    private var ratio: Double {
        switch message.kind {
        case .reel, .story: return 9.0 / 16.0
        default: return min(max(message.media?.aspectRatio ?? 1, 0.8), 1.25)
        }
    }

    var body: some View {
        let width: CGFloat = 220
        Button {
            if let link = message.share?.url {
                openLink(link)
            } else if let media = message.media {
                openMedia(media)
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                if let title = message.share?.title {
                    HStack(spacing: 7) {
                        AvatarView(url: message.share?.avatarURL, size: 24)
                        Text(title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 38)
                }

                if let media = message.media {
                    RemoteImage(url: media.thumbURL ?? media.imageURL, maxPixelSize: 640)
                        .frame(width: width, height: (width / ratio).rounded())
                        .clipped()
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: message.kind.symbolName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                                .padding(9)
                        }
                } else {
                    Label(message.kind.label, systemImage: message.kind.symbolName)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: width, height: 70)
                        .background(.quaternary.opacity(0.4))
                }

                if let subtitle = message.share?.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: width)
            .background(Color.messagesGray)
            .clipShape(.rect(cornerRadius: 17, style: .continuous))
            .contentShape(.rect(cornerRadius: 17))
        }
        .buttonStyle(PressableButtonStyle(scale: 0.97))
    }
}

/// Apple Messages' audio bubble: play button, waveform and remaining time.
private struct VoiceBubble: View {
    let url: URL?
    let outgoing: Bool
    let hasTail: Bool

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var progress: Double = 0
    @State private var duration: Double = 0

    private static let bars: [CGFloat] = [0.35, 0.6, 0.9, 0.5, 0.75, 1, 0.65, 0.4, 0.85, 0.55, 0.95, 0.45, 0.7, 0.3, 0.8, 0.5, 0.6, 0.35, 0.7, 0.45]

    var body: some View {
        let fill = outgoing ? Color.messagesBlue : Color.messagesGray
        let foreground = outgoing ? Color.white : Color.primary
        HStack(spacing: 8) {
            Button(action: toggle) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(foreground)
                    .frame(width: 22)
            }
            .buttonStyle(.plain)
            .disabled(url == nil)

            HStack(spacing: 2) {
                ForEach(Array(Self.bars.enumerated()), id: \.offset) { index, height in
                    Capsule()
                        .fill(foreground.opacity(Double(index) / Double(Self.bars.count) < progress ? 1 : 0.45))
                        .frame(width: 2.5, height: 4 + 16 * height)
                }
            }

            Text(Duration.seconds(max(0, duration * (1 - progress))).formatted(.time(pattern: .minuteSecond)))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(foreground.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(alignment: outgoing ? .bottomTrailing : .bottomLeading) {
            ZStack(alignment: outgoing ? .bottomTrailing : .bottomLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(fill)
                if hasTail {
                    BubbleTail().fill(fill).frame(width: 11, height: 16)
                        .scaleEffect(x: outgoing ? 1 : -1).offset(x: outgoing ? 5 : -5)
                }
            }
        }
        .task(id: url) {
            guard let url else { return }
            if let seconds = try? await AVURLAsset(url: url).load(.duration).seconds, seconds.isFinite { duration = seconds }
        }
        .task(id: isPlaying) {
            while isPlaying, let player {
                try? await Task.sleep(for: .milliseconds(100))
                let current = player.currentTime().seconds
                if duration > 0 { progress = min(1, current / duration) }
                if progress >= 1 {
                    isPlaying = false
                    progress = 0
                    await player.seek(to: .zero)
                }
            }
        }
        .onDisappear { player?.pause() }
    }

    private func toggle() {
        guard let url else { return }
        if player == nil { player = AVPlayer(url: url) }
        isPlaying.toggle()
        if isPlaying { player?.play() } else { player?.pause() }
    }
}

// MARK: - Formatting

extension String {
    /// One to three emoji and nothing else, which Apple Messages draws large and without a bubble.
    var isBigEmoji: Bool {
        let trimmed = trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 3 else { return false }
        return trimmed.allSatisfy { character in
            character.unicodeScalars.contains { $0.properties.isEmojiPresentation }
                || (character.unicodeScalars.first?.properties.isEmoji == true && character.unicodeScalars.count > 1)
        }
    }

    /// Detected links become tappable and underlined, as in a Messages bubble.
    func linkified(tint: Color) -> AttributedString {
        var result = AttributedString(self)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return result }
        let text = self
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url,
                  let range = Range(match.range, in: text),
                  let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[lower..<upper].link = url
            result[lower..<upper].underlineStyle = .single
            result[lower..<upper].foregroundColor = tint
        }
        return result
    }
}

extension Date {
    /// Apple Messages' conversation list: "14:32", "Dün", "Salı" or "12.10.2026".
    var messagesListStamp: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(self) { return "Dün" }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: self), to: calendar.startOfDay(for: .now)).day, days < 7 {
            return formatted(.dateTime.weekday(.wide))
        }
        return formatted(.dateTime.day(.twoDigits).month(.twoDigits).year())
    }

    /// Apple Messages' transcript separators: "**Bugün** 14:32", "**Dün** 09:10", "**12 Eki 2026** 09:10".
    var messagesTranscriptStamp: AttributedString {
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(self) {
            day = "Bugün"
        } else if calendar.isDateInYesterday(self) {
            day = "Dün"
        } else if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: self), to: calendar.startOfDay(for: .now)).day, days < 7 {
            day = formatted(.dateTime.weekday(.wide))
        } else {
            day = formatted(.dateTime.day().month(.abbreviated).year())
        }
        var bold = AttributedString(day)
        bold.font = .system(size: 11, weight: .semibold)
        return bold + AttributedString(" " + formatted(date: .omitted, time: .shortened))
    }
}
