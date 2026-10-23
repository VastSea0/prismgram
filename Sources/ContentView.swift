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
        .sheet(item: $store.sharePost) { post in
            SharePostSheet(post: post, store: store)
        }
        .sheet(isPresented: $store.isShowingInstagramSettings) {
            InstagramSettingsView(store: store)
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
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)
                        .padding(.top, 6)
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

/// The phone layout's bottom tab bar, using macOS 26's native `NSGlassEffectView` + `NSSegmentedControl`
/// capsule so pressing or dragging across tabs gets the same refractive Liquid Glass droplet lens as the
/// toolbar's segmented layout picker.
struct PhoneTabBar: View {
    @Bindable var store: AppStore
    var unreadCount: Int = 0

    var body: some View {
        LiquidGlassSegmentedTabBar(
            selectedTab: store.tab,
            onSelect: { store.select($0) }
        )
        .frame(height: 36)
        .overlay {
            if unreadCount > 0, let directIndex = InstagramTab.allCases.firstIndex(of: .direct) {
                GeometryReader { geo in
                    let count = CGFloat(InstagramTab.allCases.count)
                    let segmentWidth = geo.size.width / count
                    let centerX = segmentWidth * (CGFloat(directIndex) + 0.5) + 10
                    Text(unreadCount > 9 ? "9+" : "\(unreadCount)")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 15, minHeight: 15)
                        .background(Capsule().fill(Color.igLike))
                        .position(x: centerX, y: 8)
                }
                .allowsHitTesting(false)
            }
        }
    }
}

private struct LiquidGlassSegmentedTabBar: NSViewRepresentable {
    let selectedTab: InstagramTab
    let onSelect: (InstagramTab) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeNSView(context: Context) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.style = .regular

        let tabs = InstagramTab.allCases
        let control = NSSegmentedControl()
        control.segmentCount = tabs.count
        control.trackingMode = .selectOne
        control.segmentStyle = .automatic
        control.controlSize = .extraLarge
        control.borderShape = .capsule
        control.segmentDistribution = .fillEqually
        control.target = context.coordinator
        control.action = #selector(Coordinator.segmentChanged(_:))

        for (index, tab) in tabs.enumerated() {
            control.setTag(index, forSegment: index)
            control.setToolTip(tab.title, forSegment: index)
        }
        applyIcons(to: control, selected: selectedTab)
        glass.contentView = control
        return glass
    }

    func updateNSView(_ nsView: NSGlassEffectView, context: Context) {
        context.coordinator.onSelect = onSelect
        guard let control = nsView.contentView as? NSSegmentedControl else { return }
        applyIcons(to: control, selected: selectedTab)
    }

    private func applyIcons(to control: NSSegmentedControl, selected: InstagramTab) {
        let tabs = InstagramTab.allCases
        for (index, tab) in tabs.enumerated() {
            let isSelected = (tab == selected)
            let symbol = isSelected ? tab.filledSymbolName : tab.symbolName
            let config = NSImage.SymbolConfiguration(pointSize: 15.5, weight: isSelected ? .semibold : .regular)
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tab.title)?
                .withSymbolConfiguration(config)
            control.setImage(image, forSegment: index)
            if isSelected && control.selectedSegment != index {
                control.selectedSegment = index
            }
        }
    }

    final class Coordinator: NSObject {
        var onSelect: (InstagramTab) -> Void

        init(onSelect: @escaping (InstagramTab) -> Void) {
            self.onSelect = onSelect
        }

        @MainActor @objc func segmentChanged(_ sender: NSSegmentedControl) {
            let tabs = InstagramTab.allCases
            let index = sender.selectedSegment
            guard tabs.indices.contains(index) else { return }
            onSelect(tabs[index])
        }
    }
}
