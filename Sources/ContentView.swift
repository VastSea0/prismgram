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
        .sheet(item: $store.webPage) { page in
            WebPageSheet(request: page)
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
        if store.canGoBack {
            ToolbarItem(placement: .navigation) {
                Button {
                    store.closeOtherProfile()
                } label: {
                    Label("Geri", systemImage: "chevron.backward")
                }
                .keyboardShortcut("[", modifiers: .command)
                .help("Geri (⌘[)")
            }
        }

        if store.layoutMode == .phone {
            // A narrow window cannot fit the segmented picker and the other buttons without
            // overflowing into a ">>" menu, so the phone layout uses one compact menu.
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Görünüm", selection: $store.layoutMode) {
                        ForEach(AppLayoutMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.symbolName).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Button("Yenile", systemImage: "arrow.clockwise") { Task { await store.refresh(store.tab) } }
                    Button("Instagram Ayarları", systemImage: "gearshape") { store.isShowingInstagramSettings = true }
                } label: {
                    Label("Görünüm", systemImage: "iphone")
                }
                .menuIndicator(.hidden)
            }
        } else {
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
                .disabled(store.session != .signedIn)
                .help("Bildirimler panelini aç/kapat (⌥⌘I)")
            }
        }
    }
}

/// The phone layout's tab bar: AppKit's own segmented control, so selection slides and reacts with the
/// same Liquid Glass behaviour as the system's segmented controls (like the toolbar's layout picker).
struct PhoneTabBar: View {
    @Bindable var store: AppStore
    var unreadCount: Int = 0

    var body: some View {
        let tabs = InstagramTab.allCases
        TabSegments(tabs: tabs, selection: store.tab) { store.select($0) }
            .frame(height: 40)
            .overlay {
                if unreadCount > 0, let index = tabs.firstIndex(of: .direct) {
                    GeometryReader { geo in
                        let segment = geo.size.width / CGFloat(tabs.count)
                        Circle()
                            .fill(Color.igLike)
                            .frame(width: 7, height: 7)
                            .position(x: segment * (CGFloat(index) + 0.5) + 11, y: geo.size.height / 2 - 9)
                    }
                    .allowsHitTesting(false)
                }
            }
    }
}

private struct TabSegments: NSViewRepresentable {
    let tabs: [InstagramTab]
    let selection: InstagramTab
    let onSelect: (InstagramTab) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect, tabs: tabs) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            images: tabs.map { image(for: $0, selected: false) },
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.changed(_:))
        )
        control.segmentDistribution = .fillEqually
        control.controlSize = .extraLarge
        for (index, tab) in tabs.enumerated() {
            control.setToolTip(tab.title, forSegment: index)
            control.setLabel("", forSegment: index)
        }
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.onSelect = onSelect
        for (index, tab) in tabs.enumerated() {
            control.setImage(image(for: tab, selected: tab == selection), forSegment: index)
        }
        if let index = tabs.firstIndex(of: selection), control.selectedSegment != index {
            control.selectedSegment = index
        }
    }

    private func image(for tab: InstagramTab, selected: Bool) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 17, weight: selected ? .semibold : .regular)
        let image = NSImage(systemSymbolName: selected ? tab.filledSymbolName : tab.symbolName, accessibilityDescription: tab.title)?
            .withSymbolConfiguration(configuration)
        return image ?? NSImage()
    }

    @MainActor
    final class Coordinator: NSObject {
        var onSelect: (InstagramTab) -> Void
        let tabs: [InstagramTab]

        init(onSelect: @escaping (InstagramTab) -> Void, tabs: [InstagramTab]) {
            self.onSelect = onSelect
            self.tabs = tabs
        }

        @objc func changed(_ sender: NSSegmentedControl) {
            if let tab = tabs[safe: sender.selectedSegment] { onSelect(tab) }
        }
    }
}
