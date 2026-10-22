import SwiftUI
import AppKit

struct ContentView: View {
    @Bindable var store: AppStore

    var body: some View {
        Group {
            switch store.session {
            case .unknown:
                VStack(spacing: 12) {
                    PrismMark(size: 38)
                    ProgressView().controlSize(.regular)
                }
            case .signedOut:
                signedOut
            case .signedIn:
                signedIn
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if store.storyViewer != nil {
                StoryViewer(store: store)
                    .ignoresSafeArea()
                    .transition(.scale(scale: 0.86).combined(with: .opacity))
            }
        }
        .toolbar { toolbarContent }
        .toolbar(store.storyViewer == nil ? .visible : .hidden, for: .windowToolbar)
        .background(WindowSizer(mode: store.layoutMode))
        .sheet(item: $store.detailPost) { post in
            PostDetailView(postID: post.id, fallback: post, store: store)
        }
        .sheet(isPresented: $store.isShowingLogin) {
            LoginSheet(store: store)
        }
        .task { await store.bootstrap() }
    }

    // MARK: States

    private var signedOut: some View {
        VStack(spacing: 16) {
            PrismMark(size: 56)
            VStack(spacing: 6) {
                Text("Prismgram")
                    .font(.system(size: 22, weight: .bold))
                Text("Instagram hesabınızla giriş yaptıktan sonra akışınız, hikayeleriniz, notlarınız ve mesajlarınız tamamen yerel macOS arayüzüyle görüntülenir.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            Button("Instagram ile Giriş Yap") { store.isShowingLogin = true }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        }
        .padding(32)
    }

    @ViewBuilder
    private var signedIn: some View {
        let unreadCount = store.directThreads.filter(\.isUnread).count

        if store.layoutMode == .phone {
            detail
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    PhoneTabBar(store: store, unreadCount: unreadCount)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                }
        } else {
            NavigationSplitView {
                List(selection: sidebarSelection) {
                    Section {
                        ForEach(InstagramTab.allCases) { tab in
                            Label(tab.title, systemImage: store.tab == tab ? tab.filledSymbolName : tab.symbolName)
                                .badge(tab == .direct && unreadCount > 0 ? unreadCount : 0)
                                .tag(tab)
                        }
                    } header: {
                        HStack(spacing: 8) {
                            PrismMark(size: 16)
                            Text("Prismgram")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                        .padding(.bottom, 4)
                    }
                }
                .navigationSplitViewColumnWidth(min: 185, ideal: 215, max: 260)
            } detail: {
                detail
            }
            .inspector(isPresented: $store.isInspectorShown) {
                ActivityView(store: store)
                    .inspectorColumnWidth(min: 280, ideal: 340, max: 440)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        Group {
            switch store.tab {
            case .home: HomeView(store: store)
            case .explore: ExploreView(store: store)
            case .reels: ReelsView(store: store)
            case .activity: ActivityView(store: store)
            case .direct: MessagesView(store: store)
            case .profile: ProfileView(store: store)
            }
        }
        .navigationTitle(navigationTitle)
        .task(id: store.tab) { await store.ensureLoaded(store.tab) }
    }

    private var navigationTitle: String {
        if store.tab == .profile, let username = store.profile?.username {
            return "@\(username)"
        }
        return store.tab.title
    }

    private var sidebarSelection: Binding<InstagramTab?> {
        Binding(
            get: { store.tab },
            set: { if let tab = $0 { store.select(tab) } }
        )
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                store.closeOtherProfile()
            } label: {
                Label("Geri", systemImage: "chevron.backward")
            }
            .disabled(!store.canGoBack)
            .keyboardShortcut("[", modifiers: .command)
            .help("Geri (⌘[)")
        }

        ToolbarItem(placement: .principal) {
            Picker("Görünüm", selection: $store.layoutMode) {
                ForEach(AppLayoutMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbolName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .help("Görünüm: Telefon (⌃1), Hibrit (⌃2), Masaüstü (⌃3)")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await store.refresh(store.tab) }
            } label: {
                Label("Yenile", systemImage: "arrow.clockwise")
            }
            .disabled(store.session != .signedIn)
            .help("Yenile (⌘R)")

            Button {
                store.isInspectorShown.toggle()
            } label: {
                Label("Bildirimler Paneli", systemImage: "sidebar.trailing")
            }
            .disabled(store.layoutMode == .phone || store.session != .signedIn)
            .help("Bildirimler panelini aç/kapat (⌥⌘I)")
        }
    }
}

/// Floating tab bar for the phone layout: one glass surface, selection drawn as a plain fill (no glass on glass).
struct PhoneTabBar: View {
    @Bindable var store: AppStore
    var unreadCount: Int = 0
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(InstagramTab.allCases) { tab in
                let isSelected = store.tab == tab
                Button {
                    store.select(tab)
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: isSelected ? tab.filledSymbolName : tab.symbolName)
                            .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                            .symbolEffect(.bounce, value: isSelected)

                        if tab == .direct && unreadCount > 0 {
                            Circle()
                                .fill(Color(red: 1.0, green: 0.22, blue: 0.28))
                                .frame(width: 7, height: 7)
                                .offset(x: 4, y: -2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .contentShape(.capsule)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(.primary.opacity(0.12))
                                .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(tab.title)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(4)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}
