import SwiftUI
import AppKit

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
    @FocusState private var composerFocused: Bool

    private var thread: IGDirectThread? {
        store.directThreads.first(where: { $0.id == threadID })
    }

    var body: some View {
        if let thread {
            transcript(thread)
                .safeAreaInset(edge: .top, spacing: 0) { header(thread) }
                .safeAreaInset(edge: .bottom, spacing: 0) { composer(thread) }
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
                VStack(spacing: 4) {
                    ConversationAvatar(thread: thread, size: 40)
                    HStack(spacing: 2) {
                        Text(thread.title)
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .glassEffect(.regular, in: .capsule)
                }
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96))

            if !thread.isGroup, let user = thread.users.first {
                HStack {
                    Spacer()
                    Button { store.openProfile(of: user) } label: {
                        Image(systemName: "info")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .help("Profil")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .windowBackgroundColor).opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.bottom, -18)
            .allowsHitTesting(false)
        }
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
                                retry: { store.retryDirectMessage(message, in: thread) }
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

    // MARK: Composer (iOS 26 Messages: round + button and a glass capsule field)

    private func composer(_ thread: IGDirectThread) -> some View {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return HStack(alignment: .bottom, spacing: 8) {
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
                TextField("Mesaj", text: $draft, axis: .vertical)
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
                    .keyboardShortcut(.return, modifiers: .command)
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
        .padding(.top, 6)
        .padding(.bottom, store.layoutMode == .phone ? 72 : 10)
    }

    private func send(in thread: IGDirectThread) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        store.sendDirectMessage(text: text, in: thread)
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
        isFirstInGroup = showsTimestamp || previous?.senderFBID != message.senderFBID
        isLastInGroup = nextStartsNewSection || next?.senderFBID != message.senderFBID
        showsSenderName = isGroup && !message.isFromViewer && isFirstInGroup
        showsAvatarColumn = isGroup && !message.isFromViewer
        isLastFromViewer = message.isFromViewer && !messages[(index + 1)...].contains(where: \.isFromViewer)
    }
}

private struct MessageRow: View {
    let message: IGDirectMessage
    let layout: MessageLayout
    let avatarURL: URL?
    let retry: () -> Void

    private var isEmojiOnly: Bool { message.media == nil && message.text.isBigEmoji }

    var body: some View {
        VStack(alignment: message.isFromViewer ? .trailing : .leading, spacing: 2) {
            if layout.showsSenderName, let name = message.senderUsername {
                Text(name)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 40)
            }

            HStack(alignment: .bottom, spacing: 6) {
                if message.isFromViewer { Spacer(minLength: 56) }

                if layout.showsAvatarColumn {
                    Group {
                        if layout.isLastInGroup {
                            AvatarView(url: avatarURL, size: 26)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 26, height: 26)
                }

                if message.delivery == .failed {
                    Button(action: retry) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Tekrar gönder")
                }

                VStack(alignment: message.isFromViewer ? .trailing : .leading, spacing: 3) {
                    if let media = message.media {
                        MessageMediaBubble(media: media)
                    }
                    if !message.text.isEmpty {
                        if isEmojiOnly {
                            Text(message.text).font(.system(size: 44))
                        } else {
                            textBubble
                        }
                    }
                }
                .overlay(alignment: message.isFromViewer ? .bottomLeading : .bottomTrailing) {
                    if !message.reactions.isEmpty {
                        Text(message.reactions.prefix(3).joined())
                            .font(.system(size: 12))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.messagesGray))
                            .overlay(Capsule().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                            .offset(x: message.isFromViewer ? -10 : 10, y: 14)
                    }
                }
                .opacity(message.delivery == .sending ? 0.7 : 1)
                .contextMenu {
                    if !message.text.isEmpty {
                        Button("Kopyala") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.text, forType: .string)
                        }
                    }
                    if message.delivery == .failed {
                        Button("Tekrar Gönder", action: retry)
                    }
                }
                .help(message.timestamp.formatted(date: .abbreviated, time: .shortened))

                if !message.isFromViewer { Spacer(minLength: 56) }
            }

            if message.isFromViewer && (message.delivery != .sent) && (layout.isLastFromViewer || message.delivery == .failed) {
                Text(message.delivery == .failed ? "Gönderilmedi" : "Gönderiliyor…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(message.delivery == .failed ? Color.red : Color.secondary)
                    .padding(.trailing, 4)
                    .transition(.opacity)
            }
        }
        .padding(.top, layout.isFirstInGroup ? 8 : 2)
        .padding(.bottom, message.reactions.isEmpty ? 0 : 14)
    }

    private var textBubble: some View {
        let fill = message.isFromViewer ? Color.messagesBlue : Color.messagesGray
        return Text(message.text.linkified(tint: message.isFromViewer ? .white : .messagesBlue))
            .font(.system(size: 14))
            .foregroundStyle(message.isFromViewer ? Color.white : Color.primary)
            .tint(message.isFromViewer ? .white : .messagesBlue)
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(alignment: message.isFromViewer ? .bottomTrailing : .bottomLeading) {
                ZStack(alignment: message.isFromViewer ? .bottomTrailing : .bottomLeading) {
                    RoundedRectangle(cornerRadius: 17, style: .continuous).fill(fill)
                    if layout.isLastInGroup {
                        BubbleTail()
                            .fill(fill)
                            .frame(width: 11, height: 16)
                            .scaleEffect(x: message.isFromViewer ? 1 : -1, anchor: .center)
                            .offset(x: message.isFromViewer ? 5 : -5)
                    }
                }
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

    var body: some View {
        let width: CGFloat = 220
        RemoteImage(url: media.imageURL ?? media.thumbURL, maxPixelSize: 640)
            .frame(width: width, height: width / max(media.aspectRatio, 0.56))
            .clipShape(.rect(cornerRadius: 17, style: .continuous))
            .overlay {
                if media.videoURL != nil {
                    Image(systemName: "play.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.black.opacity(0.45)))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
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
