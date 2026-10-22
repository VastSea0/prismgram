import SwiftUI
import AppKit

// MARK: - Profile (Instagram for iOS layout)

struct ProfileView: View {
    @Bindable var store: AppStore
    @State private var followList: FollowListKind?

    private var isPhone: Bool { store.layoutMode == .phone }

    var body: some View {
        ScrollView {
            if let user = store.profile {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ProfileHeader(user: user, store: store) { followList = $0 }

                    Section {
                        grid(for: user)
                    } header: {
                        if store.canSeeContent(of: user) {
                            ProfileTabStrip(
                                sections: store.availableSections(for: user),
                                selection: store.profileSection
                            ) { store.selectProfileSection($0) }
                        }
                    }
                }
                .frame(maxWidth: isPhone ? .infinity : 935)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
            }
        }
        .id(store.profile?.id)
        .overlay {
            LoadStateView(phase: store.profilePhase, isEmpty: store.profile == nil, emptyTitle: "Profil bulunamadı", emptySymbol: "person.crop.circle") {
                Task { await store.refresh(.profile) }
            }
        }
        .sheet(item: $followList) { kind in
            if let user = store.profile {
                FollowListSheet(user: user, kind: kind, store: store)
            }
        }
    }

    @ViewBuilder
    private func grid(for user: IGUser) -> some View {
        if !store.canSeeContent(of: user) {
            VStack(spacing: 10) {
                Image(systemName: "lock")
                    .font(.system(size: 30, weight: .light))
                    .frame(width: 64, height: 64)
                    .overlay(Circle().strokeBorder(.primary, lineWidth: 1.5))
                Text("Bu hesap gizli")
                    .font(.system(size: 15, weight: .semibold))
                Text("Fotoğraflarını ve videolarını görmek için bu hesabı takip et.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .padding(.top, 40)
            .overlay(alignment: .top) { Rectangle().fill(Color.igSeparator).frame(height: 0.5) }
        } else {
            let section = store.profileSection
            let page = store.profileGrids[section] ?? AppStore.PostPage()
            if page.items.isEmpty {
                Group {
                    switch page.phase {
                    case .idle, .loading:
                        ProgressView().padding(.top, 40)
                    case .failed(let message):
                        ContentUnavailableView {
                            Label("Yüklenemedi", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(message)
                        } actions: {
                            Button("Tekrar Dene") { Task { await store.loadProfileSection(section) } }
                        }
                    case .loaded:
                        emptySection(section, isOwn: user.id == store.viewerID)
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                    ForEach(page.items) { post in
                        MediaGridTile(
                            post: post,
                            aspectRatio: section == .reels ? 9.0 / 16.0 : 3.0 / 4.0,
                            showsViewCount: section == .reels,
                            showsPin: section == .posts
                        ) {
                            store.detailPost = post
                        }
                        .onAppear {
                            if post.id == page.items.dropLast(5).last?.id || post.id == page.items.last?.id {
                                Task { await store.loadProfileSection(section, more: true) }
                            }
                        }
                    }
                }
                if page.isLoadingMore {
                    ProgressView().padding(16)
                }
            }
        }
    }

    private func emptySection(_ section: ProfileSection, isOwn: Bool) -> some View {
        let (symbol, title): (String, String) = switch section {
        case .posts: ("camera", isOwn ? "İlk gönderini paylaş" : "Henüz gönderi yok")
        case .reels: ("play.rectangle", "Henüz Reels yok")
        case .tagged: ("person.crop.square", isOwn ? "Seni içeren fotoğraflar ve videolar" : "Henüz fotoğraf yok")
        case .saved: ("bookmark", "Kaydedilen gönderi yok")
        }
        return VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .frame(width: 64, height: 64)
                .overlay(Circle().strokeBorder(.primary, lineWidth: 1.5))
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .padding(.top, 44)
    }
}

// MARK: Header

private struct ProfileHeader: View {
    let user: IGUser
    @Bindable var store: AppStore
    let showList: (FollowListKind) -> Void

    @State private var confirmUnfollow = false
    @State private var copiedLink = false

    private var isOwn: Bool { user.id == store.viewerID }
    private var storyTray: IGStoryTray? { store.stories.first(where: { $0.user.id == user.id }) }
    private var profileURL: URL { URL(string: "https://www.instagram.com/\(user.username)/")! }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 22) {
                Button {
                    if let storyTray { store.openStory(storyTray, in: store.stories) }
                } label: {
                    AvatarView(
                        url: user.avatarURL,
                        size: 86,
                        ring: storyTray.map { $0.hasUnseen ? .unseen : .seen } ?? .none
                    )
                    .frame(width: 96, height: 96)
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(storyTray == nil)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Text(user.fullName.isEmpty ? user.username : user.fullName)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        if user.isVerified { VerifiedBadge(size: 13) }
                    }

                    HStack(alignment: .top, spacing: 0) {
                        stat(user.mediaCount ?? store.profilePosts.count, "gönderi", action: nil)
                        stat(user.followerCount, "takipçi", action: store.canSeeContent(of: user) ? { showList(.followers) } : nil)
                        stat(user.followingCount, "takip", action: store.canSeeContent(of: user) ? { showList(.following) } : nil)
                    }
                }
            }

            bio

            buttons

            if !store.profileHighlights.isEmpty {
                highlights
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .confirmationDialog("@\(user.username) takibi bırakılsın mı?", isPresented: $confirmUnfollow) {
            Button(user.isRequested ? "İsteği Geri Çek" : "Takibi Bırak", role: .destructive) { store.toggleFollow(user) }
        }
    }

    private func stat(_ value: Int?, _ label: String, action: (() -> Void)?) -> some View {
        Button {
            action?()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(value.map(\.igCompact) ?? "–")
                    .font(.system(size: 16, weight: .semibold))
                    .contentTransition(.numericText(value: Double(value ?? 0)))
                Text(label)
                    .font(.system(size: 13))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }

    @ViewBuilder
    private var bio: some View {
        let hasBio = user.category != nil || !user.biography.isEmpty || user.externalURL != nil || !user.mutualFollowers.isEmpty
        if hasBio {
            VStack(alignment: .leading, spacing: 3) {
                if let category = user.category {
                    Text(category)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                if !user.biography.isEmpty {
                    Text(user.biography)
                        .font(.system(size: 13.5))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                if let link = user.externalURL {
                    Link(destination: link) {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.system(size: 11, weight: .semibold))
                            Text(Self.displayHost(link))
                                .lineLimit(1)
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.igLink)
                    }
                    .buttonStyle(.plain)
                }
                if !isOwn, !user.mutualFollowers.isEmpty {
                    Text(mutualText)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .padding(.top, 3)
                }
            }
        }
    }

    private var mutualText: AttributedString {
        let names = Array(user.mutualFollowers.prefix(2))
        let others = max(0, user.mutualFollowerCount - names.count)
        var text = AttributedString("Takip edenler: ")
        for (index, name) in names.enumerated() {
            var bold = AttributedString(name)
            bold.font = .system(size: 12.5, weight: .semibold)
            bold.foregroundColor = .primary
            text += bold
            if index < names.count - 1 { text += AttributedString(others > 0 ? ", " : " ve ") }
        }
        if others > 0 { text += AttributedString(" ve \(others.formatted()) diğer kişi") }
        return text
    }

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 6) {
            if isOwn {
                Button("Profili düzenle") {
                    store.openWeb(URL(string: "https://www.instagram.com/accounts/edit/")!, title: "Profili düzenle")
                }
                .buttonStyle(IGButtonStyle())

                Button(copiedLink ? "Bağlantı kopyalandı" : "Profili paylaş") {
                    copyProfileLink()
                }
                .buttonStyle(IGButtonStyle())
            } else {
                followButton

                Button("Mesaj") { store.openDirect(with: user) }
                    .buttonStyle(IGButtonStyle())
            }

            if isOwn {
                Button {
                    store.isShowingInstagramSettings = true
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 32)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.igSecondaryFill))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Ayarlar ve hareketler")
            } else {
                Menu {
                    Button {
                        NSWorkspace.shared.open(profileURL)
                    } label: {
                        Label("Tarayıcıda Aç", systemImage: "safari")
                    }
                    Button {
                        copyProfileLink()
                    } label: {
                        Label("Profil Bağlantısını Kopyala", systemImage: "link")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 32)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.igSecondaryFill))
                        .contentShape(.rect)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
    }

    @ViewBuilder
    private var followButton: some View {
        if user.isFollowing == true || user.isRequested {
            Button {
                confirmUnfollow = true
            } label: {
                HStack(spacing: 4) {
                    Text(user.isRequested ? "İstek gönderildi" : "Takip ediliyor")
                    if !user.isRequested {
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                    }
                }
            }
            .buttonStyle(IGButtonStyle())
        } else {
            Button(user.followsViewer ? "Sen de takip et" : "Takip et") {
                store.toggleFollow(user)
            }
            .buttonStyle(IGButtonStyle(kind: .primary))
        }
    }

    private var highlights: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 16) {
                ForEach(store.profileHighlights) { highlight in
                    Button {
                        store.openStory(highlight, in: store.profileHighlights)
                    } label: {
                        VStack(spacing: 6) {
                            AvatarView(url: highlight.coverURL ?? user.avatarURL, size: 62, ring: .seen)
                                .frame(width: 70, height: 70)
                            Text(highlight.title ?? "Öne Çıkan")
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .frame(width: 72)
                        }
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -16)
        .padding(.top, 2)
    }

    private func copyProfileLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(profileURL.absoluteString, forType: .string)
        withAnimation { copiedLink = true }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { copiedLink = false }
        }
    }

    private static func displayHost(_ url: URL) -> String {
        let text = (url.host ?? url.absoluteString) + url.path
        let trimmed = text.hasPrefix("www.") ? String(text.dropFirst(4)) : text
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }
}

// MARK: Tab strip

private struct ProfileTabStrip: View {
    let sections: [ProfileSection]
    let selection: ProfileSection
    let onSelect: (ProfileSection) -> Void
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 0) {
            ForEach(sections) { section in
                let isSelected = section == selection
                Button {
                    onSelect(section)
                } label: {
                    Image(systemName: isSelected ? section.filledSymbolName : section.symbolName)
                        .font(.system(size: 19, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .contentShape(.rect)
                        .overlay(alignment: .bottom) {
                            if isSelected {
                                Rectangle()
                                    .fill(Color.primary)
                                    .frame(height: 1.5)
                                    .matchedGeometryEffect(id: "indicator", in: indicator)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(section.title)
                .accessibilityLabel(section.title)
            }
        }
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.igSeparator).frame(height: 0.5)
        }
        .animation(.snappy(duration: 0.25), value: selection)
    }
}

struct VerifiedBadge: View {
    var size: CGFloat = 12

    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: size))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color.igBlue)
    }
}

// MARK: - Followers / following

struct FollowListSheet: View {
    let user: IGUser
    let kind: FollowListKind
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var users: [IGUser] = []
    @State private var cursor: String?
    @State private var phase: AppStore.Phase = .idle
    @State private var isLoadingMore = false
    @State private var query = ""

    private var filtered: [IGUser] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return users }
        return users.filter { $0.username.lowercased().contains(q) || $0.fullName.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { person in
                    Button {
                        dismiss()
                        store.openProfile(of: person)
                    } label: {
                        HStack(spacing: 12) {
                            AvatarView(url: person.avatarURL, size: 44)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text(person.username)
                                        .font(.system(size: 13.5, weight: .semibold))
                                    if person.isVerified { VerifiedBadge(size: 11) }
                                }
                                if !person.fullName.isEmpty {
                                    Text(person.fullName)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .onAppear {
                        if person.id == users.last?.id { Task { await load(more: true) } }
                    }
                }
                if isLoadingMore {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, placement: .toolbar, prompt: "Ara")
            .overlay {
                switch phase {
                case .idle, .loading:
                    if users.isEmpty { ProgressView() }
                case .failed(let message):
                    ContentUnavailableView("Liste yüklenemedi", systemImage: "person.2.slash", description: Text(message))
                case .loaded:
                    if users.isEmpty { ContentUnavailableView(kind == .followers ? "Henüz takipçi yok" : "Kimse takip edilmiyor", systemImage: "person.2") }
                }
            }
            .navigationTitle(kind.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
        .frame(width: 420, height: 600)
        .task { await load(more: false) }
    }

    private func load(more: Bool) async {
        if more {
            guard cursor != nil, !isLoadingMore, phase == .loaded else { return }
            isLoadingMore = true
        } else {
            phase = .loading
        }
        defer { isLoadingMore = false }
        do {
            let (page, next) = try await store.loadFollowList(userID: user.id, kind: kind, cursor: more ? cursor : nil)
            let known = Set(users.map(\.id))
            users += page.filter { !known.contains($0.id) }
            cursor = next
            phase = .loaded
        } catch {
            if more { cursor = nil } else {
                phase = .failed((error as? AppStore.RequestFailure)?.message ?? "Beklenmeyen bir hata oluştu.")
            }
        }
    }
}
