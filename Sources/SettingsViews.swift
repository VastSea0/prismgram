import SwiftUI
import AppKit
import WebKit

// MARK: - Preferences keys

enum Preference {
    static let launchLayout = "launchLayout"
    static let feedAutoplay = "feedAutoplay"
    static let feedVideosMuted = "feedVideosMuted"
    static let reelsMuted = "reelsMuted"
    static let haptics = "haptics"
}

// MARK: - Prismgram settings (⌘,)

struct PrismgramSettingsView: View {
    @Bindable var store: AppStore

    var body: some View {
        TabView {
            Tab("Genel", systemImage: "gearshape") { GeneralSettings() }
            Tab("Medya", systemImage: "play.rectangle") { MediaSettings() }
            Tab("Hesap", systemImage: "person.crop.circle") { AccountSettings(store: store) }
            Tab("Gelişmiş", systemImage: "wrench.and.screwdriver") { AdvancedSettings(store: store) }
        }
        .frame(width: 500)
    }
}

private struct GeneralSettings: View {
    @AppStorage(Preference.launchLayout) private var launchLayout = AppLayoutMode.hybrid.rawValue
    @AppStorage(Preference.haptics) private var haptics = true

    var body: some View {
        Form {
            Picker("Açılışta görünüm", selection: $launchLayout) {
                ForEach(AppLayoutMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbolName).tag(mode.rawValue)
                }
            }
            Toggle("Dokunsal geri bildirim", isOn: $haptics)
            Text("Beğenirken, sekme değiştirirken ve takip ederken Force Touch trackpad'de hafif bir tık hissedilir.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct MediaSettings: View {
    @AppStorage(Preference.feedAutoplay) private var feedAutoplay = true
    @AppStorage(Preference.feedVideosMuted) private var feedVideosMuted = true
    @AppStorage(Preference.reelsMuted) private var reelsMuted = false

    var body: some View {
        Form {
            Section("Akış") {
                Toggle("Videoları otomatik oynat", isOn: $feedAutoplay)
                Toggle("Videoları sessiz başlat", isOn: $feedVideosMuted)
            }
            Section("Reels") {
                Toggle("Reels'i sessiz başlat", isOn: $reelsMuted)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AccountSettings: View {
    @Bindable var store: AppStore
    @State private var confirmSignOut = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    AvatarView(url: store.viewer?.avatarURL, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.viewerUsername.map { "@\($0)" } ?? "Giriş yapılmadı")
                            .font(.system(size: 13.5, weight: .semibold))
                        Text(store.session == .signedIn ? "Bu Mac'te oturum açık" : "Oturum kapalı")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button("Instagram Ayarlarını Aç…") { store.isShowingInstagramSettings = true }
                    .disabled(store.session != .signedIn)
                Button("Çıkış Yap", role: .destructive) { confirmSignOut = true }
                    .disabled(store.session != .signedIn)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Instagram hesabından çıkış yapılsın mı?", isPresented: $confirmSignOut) {
            Button("Çıkış Yap", role: .destructive) { Task { await store.signOut() } }
        }
    }
}

private struct AdvancedSettings: View {
    @Bindable var store: AppStore
    @State private var cacheBytes = ImagePipeline.shared.diskUsage

    var body: some View {
        Form {
            Section("Önbellek") {
                LabeledContent("Görsel önbelleği", value: ByteCountFormatter.string(fromByteCount: Int64(cacheBytes), countStyle: .file))
                Button("Önbelleği Temizle") {
                    ImagePipeline.shared.clear()
                    cacheBytes = ImagePipeline.shared.diskUsage
                }
            }
            Section {
                Button("Instagram Motorunu Yeniden Yükle") { Task { await store.reloadEngine() } }
                    .disabled(store.session != .signedIn)
            } header: {
                Text("Gizli web motoru")
            } footer: {
                Text("Prismgram, Instagram'ın kendi web uygulamasını görünmez bir pencerede çalıştırır. Yüklemeler takılırsa motoru yeniden başlatmak çoğu sorunu çözer. Safari'nin Geliştir menüsünden incelenebilir.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Instagram settings (Instagram for iOS "Settings and activity")

struct InstagramSettingsView: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var confirmSignOut = false
    @State private var confirmPrivacy = false
    @State private var privacyError = false

    struct Item: Identifiable, Hashable {
        let title: String
        let symbol: String
        var path: String? = nil
        var action: Action? = nil
        var id: String { title }

        enum Action: Hashable { case saved, privacy, prismgram }

        var url: URL? {
            guard let path else { return nil }
            return path.hasPrefix("http") ? URL(string: path) : URL(string: "https://www.instagram.com\(path)")
        }
    }

    private let sections: [(String, [Item])] = [
        ("Hesabın", [
            Item(title: "Hesap Merkezi", symbol: "person.crop.circle", path: "https://accountscenter.instagram.com/"),
        ]),
        ("Instagram'ı nasıl kullanıyorsun", [
            Item(title: "Kaydedilenler", symbol: "bookmark", action: .saved),
            Item(title: "Arşiv", symbol: "clock.arrow.circlepath", path: "/archive/stories/"),
            Item(title: "Hareketlerin", symbol: "chart.bar", path: "/your_activity/interactions/likes/"),
            Item(title: "Bildirimler", symbol: "bell", path: "/accounts/notifications/"),
        ]),
        ("İçeriğini kimler görebilir", [
            Item(title: "Hesap gizliliği", symbol: "lock", action: .privacy),
            Item(title: "Yakın Arkadaşlar", symbol: "star.circle", path: "/accounts/close_friends/"),
            Item(title: "Engellenenler", symbol: "nosign", path: "/accounts/blocked_accounts/"),
            Item(title: "Hikaye ve canlı yayını gizle", symbol: "eye.slash", path: "/accounts/hide_story_and_live_from/"),
        ]),
        ("Başkalarının seninle nasıl etkileşim kurabileceği", [
            Item(title: "Mesajlar ve hikaye yanıtları", symbol: "bubble.left", path: "/accounts/messages_and_story_replies/"),
            Item(title: "Etiketler ve bahsetmeler", symbol: "at", path: "/accounts/tags_and_mentions/"),
            Item(title: "Yorumlar", symbol: "bubble.right", path: "/accounts/comments/"),
            Item(title: "Paylaşım ve yeniden kullanım", symbol: "arrow.2.squarepath", path: "/accounts/sharing_and_reuse/"),
            Item(title: "Kısıtlanan hesaplar", symbol: "person.crop.circle.badge.exclamationmark", path: "/accounts/restricted_accounts/"),
            Item(title: "Gizlenen kelimeler", symbol: "textformat", path: "/accounts/hidden_words/"),
        ]),
        ("Ne göreceğin", [
            Item(title: "Sessize alınan hesaplar", symbol: "speaker.slash", path: "/accounts/muted_accounts/"),
            Item(title: "İçerik tercihleri", symbol: "slider.horizontal.3", path: "/accounts/content_preferences/"),
            Item(title: "Beğeni ve paylaşım sayıları", symbol: "heart.slash", path: "/accounts/like_count/"),
        ]),
        ("Uygulaman ve medyan", [
            Item(title: "Dil", symbol: "globe", path: "/accounts/language_preferences/"),
            Item(title: "Prismgram ayarları", symbol: "macwindow", action: .prismgram),
        ]),
        ("Daha fazla bilgi ve destek", [
            Item(title: "Yardım", symbol: "questionmark.circle", path: "https://help.instagram.com/"),
            Item(title: "Gizlilik Merkezi", symbol: "checkmark.shield", path: "https://privacycenter.instagram.com/"),
        ]),
    ]

    private var filtered: [(String, [Item])] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return sections }
        return sections.compactMap { title, items in
            let hits = items.filter { $0.title.lowercased().contains(q) }
            return hits.isEmpty ? nil : (title, hits)
        }
    }

    private var isPrivate: Bool? {
        guard let me = store.viewer, store.profile?.id == store.viewerID else { return nil }
        return me.isPrivate
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered, id: \.0) { title, items in
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 18)
                            .padding(.bottom, 4)
                        ForEach(items) { item in row(item) }
                        Rectangle().fill(Color.igSeparator).frame(height: 6).opacity(0.5).padding(.top, 10)
                    }

                    if query.isEmpty {
                        Text("Giriş")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 18)
                        Button("Çıkış yap") { confirmSignOut = true }
                            .buttonStyle(.plain)
                            .font(.system(size: 15))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                }
                .padding(.bottom, 20)
            }
            .searchable(text: $query, placement: .toolbar, prompt: "Ara")
            .navigationTitle("Ayarlar ve hareketler")
            .navigationDestination(for: Item.self) { item in
                if let url = item.url {
                    SettingsWebPage(url: url).navigationTitle(item.title)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
        .frame(width: 480, height: 720)
        .confirmationDialog("Instagram hesabından çıkış yapılsın mı?", isPresented: $confirmSignOut) {
            Button("Çıkış Yap", role: .destructive) {
                dismiss()
                Task { await store.signOut() }
            }
        }
        .confirmationDialog(
            isPrivate == true ? "Herkese açık hesaba geçilsin mi?" : "Gizli hesaba geçilsin mi?",
            isPresented: $confirmPrivacy
        ) {
            Button(isPrivate == true ? "Herkese Açık Yap" : "Gizli Yap") {
                Task { privacyError = !(await store.setAccountPrivate(!(isPrivate ?? false))) }
            }
        } message: {
            Text(isPrivate == true
                 ? "Herkes profilini ve gönderilerini görebilir."
                 : "Yalnızca onayladığın takipçiler fotoğraflarını ve videolarını görebilir.")
        }
        .alert("Hesap gizliliği değiştirilemedi", isPresented: $privacyError) {}
        .task {
            if store.profile?.id != store.viewerID { store.select(.profile) }
        }
    }

    @ViewBuilder
    private func row(_ item: Item) -> some View {
        let label = HStack(spacing: 14) {
            Image(systemName: item.symbol)
                .font(.system(size: 18))
                .frame(width: 26)
            Text(item.title)
                .font(.system(size: 14.5))
            Spacer(minLength: 8)
            if item.action == .privacy, let isPrivate {
                Text(isPrivate ? "Gizli" : "Herkese açık")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(.rect)

        switch item.action {
        case .saved:
            Button {
                dismiss()
                store.select(.profile)
                store.selectProfileSection(.saved)
            } label: { label }
            .buttonStyle(.plain)
        case .privacy:
            Button { confirmPrivacy = true } label: { label }
                .buttonStyle(.plain)
                .disabled(isPrivate == nil)
        case .prismgram:
            SettingsLink { label }
                .buttonStyle(.plain)
        case nil:
            NavigationLink(value: item) { label }
                .buttonStyle(.plain)
        }
    }
}

private struct SettingsWebPage: View {
    let url: URL
    @State private var title = ""
    @State private var isLoading = true

    var body: some View {
        InstagramPageView(url: url, title: $title, isLoading: $isLoading)
            .overlay(alignment: .top) {
                if isLoading { ProgressView().controlSize(.small).padding(8) }
            }
    }
}
