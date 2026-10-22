import SwiftUI
import AppKit

struct ContentView: View {
    @Bindable var store: AppStore

    var body: some View {
        Group {
            switch store.session {
            case .unknown:
                ProgressView().controlSize(.large)
            case .signedOut:
                signedOut
            case .signedIn:
                signedIn
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar { toolbarContent }
        .background(WindowSizer(mode: store.layoutMode))
        .sheet(item: $store.storyViewer) { tray in
            StoryViewer(tray: tray, store: store)
        }
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
        ContentUnavailableView {
            Label("Instagram'a Giriş Yapın", systemImage: "person.crop.circle.badge.questionmark")
        } description: {
            Text("Hesabınızla giriş yaptıktan sonra akışınız, hikayeleriniz ve Keşfet burada yerel olarak görüntülenir.")
        } actions: {
            Button("Giriş Yap") { store.isShowingLogin = true }
                .buttonStyle(.glassProminent)
        }
    }

    @ViewBuilder
    private var signedIn: some View {
        if store.layoutMode == .phone {
            detail
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    PhoneTabBar(store: store)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                }
        } else {
            NavigationSplitView {
                List(selection: sidebarSelection) {
                    ForEach(InstagramTab.allCases) { tab in
                        Label(tab.title, systemImage: tab.symbolName).tag(tab)
                    }
                }
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
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
        .navigationTitle(store.tab.title)
        .task(id: store.tab) { await store.ensureLoaded(store.tab) }
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
                Task { await store.ensureLoaded(.profile) }
            } label: {
                Label("Geri", systemImage: "chevron.backward")
            }
            .disabled(!(store.tab == .profile && store.profileUserID != nil))
            .help("Kendi profiline dön")
        }

        ToolbarItem(placement: .principal) {
            Picker("Görünüm", selection: $store.layoutMode) {
                ForEach(AppLayoutMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbolName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .help("Görünüm: Telefon, Hibrit, Masaüstü")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await store.refresh(store.tab) }
            } label: {
                Label("Yenile", systemImage: "arrow.clockwise")
            }
            .disabled(store.session != .signedIn)
            .help("Yenile")

            Button {
                store.isInspectorShown.toggle()
            } label: {
                Label("Bildirimler Paneli", systemImage: "sidebar.trailing")
            }
            .disabled(store.layoutMode == .phone || store.session != .signedIn)
            .help("Bildirimler panelini aç/kapat")
        }
    }
}

/// Floating tab bar for the phone layout: one glass surface, selection drawn as a plain fill (no glass on glass).
struct PhoneTabBar: View {
    @Bindable var store: AppStore
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(InstagramTab.allCases) { tab in
                let isSelected = store.tab == tab
                Button {
                    store.select(tab)
                } label: {
                    Image(systemName: isSelected ? tab.filledSymbolName : tab.symbolName)
                        .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
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
