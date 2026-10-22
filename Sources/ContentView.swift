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

/// The phone layout's tab bar, after the iOS 26 tab bar Instagram uses: a floating Liquid Glass capsule
/// with a selection pill that slides between tabs, icons that spring when pressed, and the viewer's
/// photo for Profile.
struct PhoneTabBar: View {
    @Bindable var store: AppStore
    var unreadCount: Int = 0
    @Namespace private var selection

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 0) {
                ForEach(InstagramTab.allCases) { tab in
                    let isSelected = store.tab == tab
                    Button {
                        store.select(tab)
                    } label: {
                        icon(for: tab, selected: isSelected)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.1))
                                        .matchedGeometryEffect(id: "selection", in: selection)
                                }
                            }
                            .overlay(alignment: .topTrailing) {
                                if tab == .direct && unreadCount > 0 {
                                    Text(unreadCount > 9 ? "9+" : "\(unreadCount)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .frame(minWidth: 16, minHeight: 16)
                                        .background(Capsule().fill(Color.igLike))
                                        .offset(x: -10, y: 5)
                                }
                            }
                            .contentShape(.capsule)
                    }
                    .buttonStyle(TabPressStyle())
                    .help(tab.title)
                    .accessibilityLabel(tab.title)
                }
            }
            .padding(4)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.74), value: store.tab)
    }

    @ViewBuilder
    private func icon(for tab: InstagramTab, selected: Bool) -> some View {
        if tab == .profile {
            AvatarView(url: store.viewer?.avatarURL, size: 25)
                .padding(2)
                .overlay(Circle().strokeBorder(Color.primary, lineWidth: selected ? 1.5 : 0))
        } else {
            Image(systemName: selected ? tab.filledSymbolName : tab.symbolName)
                .font(.system(size: 21, weight: selected ? .semibold : .regular))
                .foregroundStyle(.primary)
                .symbolEffect(.bounce, value: selected)
        }
    }
}

/// Tab icons shrink a little under the finger and spring back, as in iOS.
private struct TabPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}
