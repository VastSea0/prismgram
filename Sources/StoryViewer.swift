import SwiftUI
import AVKit

// MARK: - Story viewer (Instagram for iOS)
//
// Full-window, black, one 9:16 canvas per person. Tap the left third to go back, anywhere else to go
// forward, press and hold to pause (the chrome fades out), drag down to close. Moving between people
// turns a cube, like the iOS app. On wider layouts the canvas sits centred with arrows beside it.

struct StoryViewer: View {
    @Bindable var store: AppStore
    @State private var forward = true
    @State private var dragOffset: CGFloat = 0
    @State private var isShowingDetails = false

    var body: some View {
        GeometryReader { geo in
            let isPhone = store.layoutMode == .phone
            let canvas = canvasSize(in: geo.size, isPhone: isPhone)
            let dragProgress = min(1, max(0, dragOffset) / 400)

            ZStack {
                Color.black
                    .opacity(isPhone ? 1 - dragProgress * 0.7 : 0.94 - dragProgress * 0.6)
                    .ignoresSafeArea()
                    .onTapGesture {
                        if isShowingDetails {
                            withAnimation(.spring(duration: 0.3, bounce: 0.1)) { isShowingDetails = false }
                        } else if !isPhone {
                            store.closeStory()
                        }
                    }

                if let tray = store.storyViewer {
                    StoryCanvas(
                        tray: tray,
                        store: store,
                        isPhone: isPhone,
                        isShowingViewers: $isShowingDetails
                    ) { delta in
                        isShowingDetails = false
                        move(delta)
                    }
                    .frame(width: canvas.width, height: canvas.height)
                    .clipShape(.rect(cornerRadius: isPhone ? 0 : 10, style: .continuous))
                    .id(tray.id)
                    .transition(.cube(forward: forward, width: canvas.width))
                    .zIndex(1)
                }

                if !isPhone {
                    HStack(spacing: 0) {
                        sideButton("chevron.left", enabled: store.adjacentStory(-1) != nil) {
                            isShowingDetails = false
                            move(-1)
                        }
                        Spacer().frame(width: canvas.width + 36)
                        sideButton("chevron.right", enabled: store.adjacentStory(1) != nil) {
                            isShowingDetails = false
                            move(1)
                        }
                    }
                    .zIndex(2)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .offset(y: max(0, dragOffset))
            .scaleEffect(1 - dragProgress * 0.15)
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onChanged { value in
                        guard !isShowingDetails else { return }
                        if value.translation.height > 0 && abs(value.translation.height) > abs(value.translation.width) {
                            dragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if isShowingDetails {
                            if value.translation.height > 70 || value.predictedEndTranslation.height > 160 {
                                withAnimation(.spring(duration: 0.3, bounce: 0.1)) { isShowingDetails = false }
                            }
                            return
                        }
                        if value.translation.height < -45 && abs(value.translation.height) > abs(value.translation.width) {
                            withAnimation(.spring(duration: 0.32, bounce: 0.12)) { isShowingDetails = true }
                        } else if value.translation.height > 140 || value.predictedEndTranslation.height > 320 {
                            store.closeStory()
                        } else if abs(value.translation.width) > 90 && abs(value.translation.width) > abs(value.translation.height) {
                            move(value.translation.width < 0 ? 1 : -1)
                        }
                        withAnimation(.spring(duration: 0.3, bounce: 0.2)) { dragOffset = 0 }
                    }
            )
            .overlay(alignment: .topTrailing) {
                if !isPhone {
                    Button { store.closeStory() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                }
            }
        }
        // Arrow and space keys are handled by the focused canvas; these bubble up from it.
        .onKeyPress(.escape) {
            if isShowingDetails {
                withAnimation(.spring(duration: 0.28, bounce: 0.1)) { isShowingDetails = false }
            } else {
                store.closeStory()
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            withAnimation(.spring(duration: 0.32, bounce: 0.12)) { isShowingDetails = true }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if isShowingDetails {
                withAnimation(.spring(duration: 0.28, bounce: 0.1)) { isShowingDetails = false }
            } else {
                store.closeStory()
            }
            return .handled
        }
    }

    private func canvasSize(in size: CGSize, isPhone: Bool) -> CGSize {
        if isPhone { return size }
        let height = min(size.height - 32, 920)
        return CGSize(width: (height * 9 / 16).rounded(), height: height.rounded())
    }

    private func move(_ delta: Int) {
        forward = delta > 0
        withAnimation(.spring(duration: 0.5, bounce: 0.04)) {
            store.showAdjacentStory(delta)
        }
    }

    private func sideButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(0.9)))
        }
        .buttonStyle(PressableButtonStyle(scale: 0.88))
        .opacity(enabled ? 1 : 0)
        .disabled(!enabled)
    }
}

// MARK: One person's story

private struct StoryCanvas: View {
    let tray: IGStoryTray
    @Bindable var store: AppStore
    let isPhone: Bool
    @Binding var isShowingViewers: Bool
    let onLeaveTray: (Int) -> Void

    @State private var index: Int
    @State private var clock = StoryClock()
    @State private var isHolding = false
    @State private var player = AVPlayer()
    @State private var isMediaReady = false
    @State private var isMuted = false
    @State private var pressStart: Date?
    @State private var isLoadingViewers = false
    @State private var viewerSearch = ""
    @State private var replyDraft = ""
    @State private var isSendingReply = false
    @State private var sentReplyToast = false
    @State private var likedSlides: Set<String> = []
    @FocusState private var isFocused: Bool
    @FocusState private var isReplyFocused: Bool

    init(
        tray: IGStoryTray,
        store: AppStore,
        isPhone: Bool,
        isShowingViewers: Binding<Bool>,
        onLeaveTray: @escaping (Int) -> Void
    ) {
        self.tray = tray
        self.store = store
        self.isPhone = isPhone
        self._isShowingViewers = isShowingViewers
        self.onLeaveTray = onLeaveTray
        _index = State(initialValue: tray.resumeIndex)
    }

    private var slide: IGMediaItem? { tray.slides[safe: index] }

    private var isOwnStory: Bool {
        tray.user.id == store.viewerID
            || (store.viewerUsername != nil && tray.user.username.lowercased() == store.viewerUsername?.lowercased())
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color(white: 0.08)

                ZStack {
                    media

                    if !isMediaReady || slide == nil {
                        if tray.slides.isEmpty && !store.isLoadingStory(tray.id) {
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle")
                                    .font(.system(size: 28))
                                Text("Hikaye yüklenemedi")
                                    .font(.system(size: 14, weight: .semibold))
                                Button("Tekrar Dene") { Task { await store.loadStorySlides(for: tray) } }
                                    .buttonStyle(.glass)
                            }
                            .foregroundStyle(.white)
                        } else {
                            ProgressView().tint(.white).controlSize(.large)
                        }
                    }

                    touchLayer

                    chrome
                        .opacity(isHolding || isShowingViewers ? 0 : 1)
                        .animation(.easeOut(duration: 0.2), value: isHolding || isShowingViewers)
                }
                .scaleEffect(isShowingViewers ? 0.34 : 1.0, anchor: .top)
                .offset(y: isShowingViewers ? 14 : 0)
                .allowsHitTesting(!isShowingViewers)
                .animation(.spring(duration: 0.32, bounce: 0.1), value: isShowingViewers)

                if isShowingViewers {
                    Color.black.opacity(0.25)
                        .contentShape(.rect)
                        .onTapGesture {
                            withAnimation(.spring(duration: 0.28, bounce: 0.1)) { isShowingViewers = false }
                        }
                        .transition(.opacity)

                    if let slide {
                        storyDetailsSheet(slide: slide, height: geo.size.height * 0.62)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .zIndex(3)
                    }
                }
            }
        }
        .task(id: "\(tray.slides.count)-\(index)") { await play() }
        .onChange(of: clock.isPaused) { _, paused in
            if paused { player.pause() } else if slide?.videoURL != nil { player.play() }
        }
        .onChange(of: isShowingViewers) { _, showing in
            clock.isPaused = showing || isReplyFocused
            if showing, let slide {
                Task { await refreshViewers(for: slide) }
            }
        }
        .onChange(of: isReplyFocused) { _, focused in
            clock.isPaused = focused || isShowingViewers
        }
        .onChange(of: isMuted) { _, muted in player.isMuted = muted }
        .onChange(of: tray.slides.count) { old, _ in
            if old == 0 { index = tray.resumeIndex }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onDisappear {
            clock.stop()
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        .onKeyPress(.leftArrow) {
            guard !isReplyFocused else { return .ignored }
            isShowingViewers = false
            step(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard !isReplyFocused else { return .ignored }
            isShowingViewers = false
            step(1)
            return .handled
        }
        .onKeyPress(.space) {
            guard !isReplyFocused else { return .ignored }
            clock.isPaused.toggle()
            return .handled
        }
    }

    // MARK: Media

    @ViewBuilder
    private var media: some View {
        if let slide {
            if slide.videoURL != nil {
                PlayerSurface(player: player, showsControls: false, fillsFrame: true)
                    .allowsHitTesting(false)
            } else {
                CachedImage(url: slide.imageURL, maxPixelSize: 1440) { _ in Color.clear }
                    .id(slide.id)
            }
        }
    }

    private func play() async {
        clock.stop()
        isMediaReady = false
        guard let slide else { return }
        let next = tray.slides[safe: index + 1]
        ImagePipeline.shared.prefetch([next?.imageURL], maxPixelSize: 1440)

        if isOwnStory || slide.viewerCount != nil || !slide.viewers.isEmpty {
            Task { await refreshViewers(for: slide) }
        }

        var duration: Double = 5
        if let videoURL = slide.videoURL {
            let asset = AVURLAsset(url: videoURL)
            let item = AVPlayerItem(asset: asset)
            player.replaceCurrentItem(with: item)
            player.isMuted = isMuted
            if let loaded = try? await asset.load(.duration), loaded.seconds.isFinite, loaded.seconds > 0 {
                duration = loaded.seconds
            } else {
                duration = slide.duration ?? 15
            }
            guard !Task.isCancelled else { return }
            if !isShowingViewers && !isReplyFocused {
                player.play()
            }
        } else {
            player.replaceCurrentItem(with: nil)
            if let url = slide.imageURL {
                _ = await ImagePipeline.shared.image(for: url, maxPixelSize: 1440)
            }
            guard !Task.isCancelled else { return }
        }
        isMediaReady = true
        clock.start(duration: duration) { step(1) }
        if isShowingViewers || isReplyFocused {
            clock.isPaused = true
        }
    }

    private func refreshViewers(for slide: IGMediaItem) async {
        guard !isLoadingViewers else { return }
        isLoadingViewers = true
        defer { isLoadingViewers = false }
        await store.loadStoryViewers(trayID: tray.id, slideID: slide.id)
    }

    private func step(_ delta: Int) {
        let target = index + delta
        if target < 0 {
            if store.adjacentStory(-1) != nil {
                onLeaveTray(-1)
            } else {
                clock.restart()
                if slide?.videoURL != nil { player.seek(to: .zero) }
            }
        } else if target >= tray.slides.count {
            onLeaveTray(1)
        } else {
            index = target
        }
    }

    // MARK: Touch

    /// Taps advance or go back; holding pauses; dragging up opens the story insights & viewers drawer.
    private var touchLayer: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if abs(value.translation.height) > 16 || abs(value.translation.width) > 16 {
                                pressStart = nil
                                if isHolding {
                                    isHolding = false
                                    clock.isPaused = false
                                }
                                return
                            }
                            guard pressStart == nil else { return }
                            pressStart = .now
                            Task {
                                try? await Task.sleep(for: .milliseconds(220))
                                if pressStart != nil {
                                    isHolding = true
                                    clock.isPaused = true
                                }
                            }
                        }
                        .onEnded { value in
                            let wasHolding = isHolding
                            pressStart = nil
                            isHolding = false
                            clock.isPaused = isShowingViewers || isReplyFocused

                            // Swipe up -> open story details & viewers sheet
                            if value.translation.height < -32 && abs(value.translation.height) > abs(value.translation.width) {
                                withAnimation(.spring(duration: 0.32, bounce: 0.12)) {
                                    isShowingViewers = true
                                }
                                return
                            }
                            // Swipe down -> close story viewer
                            if value.translation.height > 110 && abs(value.translation.height) > abs(value.translation.width) {
                                store.closeStory()
                                return
                            }
                            // Horizontal swipe -> adjacent person's story
                            if abs(value.translation.width) > 80 && abs(value.translation.width) > abs(value.translation.height) {
                                onLeaveTray(value.translation.width < 0 ? 1 : -1)
                                return
                            }

                            let moved = abs(value.translation.width) > 10 || abs(value.translation.height) > 10
                            guard !wasHolding, !moved else { return }
                            if isReplyFocused {
                                isReplyFocused = false
                                return
                            }
                            step(value.location.x < geo.size.width * 0.3 ? -1 : 1)
                        }
                )
        }
    }

    // MARK: Chrome

    private var chrome: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                StoryProgressBar(count: max(tray.slides.count, 1), index: index, clock: clock)

                HStack(spacing: 8) {
                    Button {
                        store.openProfile(of: tray.user)
                    } label: {
                        HStack(spacing: 8) {
                            AvatarView(url: tray.title == nil ? tray.user.avatarURL : (tray.coverURL ?? tray.user.avatarURL), size: 32)
                            Text(tray.title ?? (isOwnStory ? "Hikayen" : tray.user.username))
                                .font(.system(size: 13.5, weight: .semibold))
                                .lineLimit(1)
                            if tray.user.isVerified && tray.title == nil {
                                VerifiedBadge(size: 11)
                            }
                            if let date = slide?.takenAt {
                                Text("\(date.igAge) · \(date.formatted(date: .omitted, time: .shortened))")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 4)

                    if clock.isPaused && !isHolding {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 15))
                            .transition(.scale.combined(with: .opacity))
                    }

                    if slide?.videoURL != nil {
                        chromeButton(isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") { isMuted.toggle() }
                    }

                    Menu {
                        Button {
                            withAnimation(.spring(duration: 0.32, bounce: 0.12)) {
                                isShowingViewers = true
                            }
                        } label: {
                            Label(isOwnStory ? "Hikaye Detayları ve İzleyenler" : "Hikaye Bilgileri", systemImage: "eye")
                        }
                        Button {
                            NSWorkspace.shared.open(URL(string: "https://www.instagram.com/stories/\(tray.user.username)/")!)
                        } label: {
                            Label("Tarayıcıda Aç", systemImage: "safari")
                        }
                        Button {
                            store.openProfile(of: tray.user)
                        } label: {
                            Label("Profili Gör", systemImage: "person.crop.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .bold))
                            .frame(width: 30, height: 30)
                            .contentShape(.rect)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()

                    if isPhone {
                        chromeButton("xmark") { store.closeStory() }
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
            }
            .padding(.horizontal, 10)
            .padding(.top, isPhone ? 10 : 12)
            .padding(.bottom, 26)
            .background(
                LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
            )

            Spacer()

            if let slide {
                bottomBar(for: slide)
            }
        }
    }

    @ViewBuilder
    private func bottomBar(for slide: IGMediaItem) -> some View {
        let hasViewerInfo = isOwnStory || slide.viewerCount != nil || !slide.viewers.isEmpty
        if hasViewerInfo {
            let count = max(slide.viewerCount ?? 0, slide.viewers.count)
            HStack {
                Button {
                    withAnimation(.spring(duration: 0.32, bounce: 0.12)) {
                        isShowingViewers = true
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 10, weight: .bold))
                            Text("Detaylar için yukarı kaydır")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.78))

                        HStack(spacing: 8) {
                            if !slide.viewers.isEmpty {
                                HStack(spacing: -8) {
                                    ForEach(slide.viewers.prefix(3)) { viewer in
                                        AvatarView(url: viewer.avatarURL, size: 26)
                                            .overlay(Circle().strokeBorder(.black, lineWidth: 1.5))
                                    }
                                }
                            } else {
                                Image(systemName: "eye.fill")
                                    .font(.system(size: 13.5, weight: .semibold))
                            }
                            Text(count > 0 ? "\(count) kişi gördü" : (isLoadingViewers ? "İzleyenler yükleniyor…" : "Henüz görüntüleyen yok"))
                                .font(.system(size: 13.5, weight: .semibold))
                            if isLoadingViewers {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(.white)
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.black.opacity(0.5)))
                    }
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, isPhone ? 18 : 14)
            .padding(.top, 16)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
            )
        } else {
            // Native Instagram bottom bar on other people's stories: reply field + heart + share
            let isLiked = likedSlides.contains(slide.id)
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    TextField(
                        "\(tray.user.username) adlı kişiye mesaj gönder…",
                        text: $replyDraft
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.white)
                    .focused($isReplyFocused)
                    .onSubmit { sendReply(for: slide) }

                    if sentReplyToast {
                        Text("Gönderildi ✓")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    } else if !replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("Gönder") { sendReply(for: slide) }
                            .buttonStyle(.plain)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .disabled(isSendingReply)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(.black.opacity(0.35))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                )

                Button {
                    withAnimation(.spring(duration: 0.3, bounce: 0.5)) {
                        if isLiked {
                            likedSlides.remove(slide.id)
                        } else {
                            likedSlides.insert(slide.id)
                            Task { _ = await store.replyToStory(tray, slide: slide, text: "❤️") }
                        }
                    }
                } label: {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 22))
                        .foregroundStyle(isLiked ? Color.igLike : .white)
                        .symbolEffect(.bounce, value: isLiked)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)

                Button {
                    store.closeStory()
                    store.openDirect(with: tray.user)
                } label: {
                    Image(systemName: "paperplane")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, isPhone ? 18 : 14)
            .padding(.top, 16)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
            )
        }
    }

    private func sendReply(for slide: IGMediaItem) {
        let text = replyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSendingReply else { return }
        isSendingReply = true
        replyDraft = ""
        isReplyFocused = false
        Task {
            let ok = await store.replyToStory(tray, slide: slide, text: text)
            isSendingReply = false
            if ok {
                withAnimation { sentReplyToast = true }
                try? await Task.sleep(for: .seconds(1.8))
                withAnimation { sentReplyToast = false }
            }
        }
    }

    // MARK: Slide-up Story Insights & Viewers Sheet

    private func storyDetailsSheet(slide: IGMediaItem, height: CGFloat) -> some View {
        let count = max(slide.viewerCount ?? 0, slide.viewers.count)
        let query = viewerSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filteredViewers = query.isEmpty ? slide.viewers : slide.viewers.filter {
            $0.username.lowercased().contains(query) || $0.fullName.lowercased().contains(query)
        }

        return VStack(alignment: .leading, spacing: 0) {
            // Drag indicator
            HStack {
                Spacer()
                Capsule()
                    .fill(.secondary.opacity(0.45))
                    .frame(width: 36, height: 4.5)
                Spacer()
            }
            .padding(.top, 8)
            .padding(.bottom, 6)

            // Header: viewer count + timestamp + actions
            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("\(count) görüntüleme")
                        .font(.system(size: 15, weight: .bold))
                        .contentTransition(.numericText(value: Double(count)))
                    if isLoadingViewers {
                        ProgressView().controlSize(.small)
                    }
                }

                Spacer()

                if let date = slide.takenAt {
                    Text("\(date.igAge) · \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await refreshViewers(for: slide) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("İzleyenleri yenile")

                Button {
                    withAnimation(.spring(duration: 0.28, bounce: 0.1)) { isShowingViewers = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            if slide.viewers.count > 5 {
                TextField("İzleyenlerde ara…", text: $viewerSearch)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }

            Divider()

            if isLoadingViewers && slide.viewers.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("İzleyenler yükleniyor…")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredViewers.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                    Text(
                        !query.isEmpty
                            ? "Sonuç bulunamadı"
                            : (count > 0
                                ? "\(count) kişi bu hikayeyi gördü.\nDetaylı izleyen listesi yalnızca kendi aktif hikayelerinde görünür."
                                : "Bu hikayeyi henüz kimse görüntülemedi.")
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredViewers) { viewer in
                            let hasLiked = slide.likedViewerIDs.contains(viewer.id)
                            HStack(spacing: 12) {
                                Button {
                                    isShowingViewers = false
                                    store.openProfile(of: viewer)
                                } label: {
                                    HStack(spacing: 12) {
                                        AvatarView(url: viewer.avatarURL, size: 40)
                                            .overlay(alignment: .bottomTrailing) {
                                                if hasLiked {
                                                    Image(systemName: "heart.fill")
                                                        .font(.system(size: 9, weight: .bold))
                                                        .foregroundStyle(.white)
                                                        .padding(3.5)
                                                        .background(Circle().fill(Color.igLike))
                                                        .offset(x: 2, y: 2)
                                                }
                                            }
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 4) {
                                                Text(viewer.username)
                                                    .font(.system(size: 13.5, weight: .semibold))
                                                if viewer.isVerified {
                                                    VerifiedBadge(size: 11)
                                                }
                                            }
                                            if !viewer.fullName.isEmpty {
                                                Text(viewer.fullName)
                                                    .font(.system(size: 12.5))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    isShowingViewers = false
                                    store.closeStory()
                                    store.openDirect(with: viewer)
                                } label: {
                                    Image(systemName: "paperplane")
                                        .font(.system(size: 15))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 32, height: 32)
                                        .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .help("@\(viewer.username) kişisine mesaj gönder")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(.regularMaterial, in: .rect(topLeadingRadius: 18, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 18, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    if value.translation.height > 45 || value.predictedEndTranslation.height > 120 {
                        withAnimation(.spring(duration: 0.28, bounce: 0.1)) {
                            isShowingViewers = false
                        }
                    }
                }
        )
    }

    private func chromeButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 30, height: 30)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: Progress

/// Drives a story's progress. Only the progress bar reads `progress`, so ticking does not redraw the media.
@MainActor
@Observable
final class StoryClock {
    var progress: Double = 0
    var isPaused = false
    private var task: Task<Void, Never>?

    func start(duration: Double, onFinish: @escaping @MainActor () -> Void) {
        task?.cancel()
        progress = 0
        task = Task { [weak self] in
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard let self, !Task.isCancelled else { return }
                let now = ContinuousClock.now
                let elapsed = now - last
                last = now
                guard !self.isPaused else { continue }
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                self.progress = min(1, self.progress + seconds / max(duration, 0.5))
                if self.progress >= 1 {
                    onFinish()
                    return
                }
            }
        }
    }

    func restart() { progress = 0 }

    func stop() {
        task?.cancel()
        task = nil
        progress = 0
    }
}

private struct StoryProgressBar: View {
    let count: Int
    let index: Int
    let clock: StoryClock

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { position in
                GeometryReader { geo in
                    Capsule()
                        .fill(.white.opacity(0.35))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(.white)
                                .frame(width: geo.size.width * fill(position))
                        }
                }
                .frame(height: 2)
            }
        }
    }

    private func fill(_ position: Int) -> CGFloat {
        if position < index { return 1 }
        if position > index { return 0 }
        return clock.progress
    }
}

// MARK: Cube transition

private struct CubeFace: ViewModifier {
    let angle: Double
    let offset: CGFloat
    let anchor: UnitPoint

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), anchor: anchor, perspective: 0.5)
            .offset(x: offset)
    }
}

extension AnyTransition {
    /// The face of a cube turning left (`forward`) or right, the way Instagram moves between people's stories.
    static func cube(forward: Bool, width: CGFloat) -> AnyTransition {
        let sign: Double = forward ? 1 : -1
        return .asymmetric(
            insertion: .modifier(
                active: CubeFace(angle: 90 * sign, offset: width * sign, anchor: forward ? .leading : .trailing),
                identity: CubeFace(angle: 0, offset: 0, anchor: forward ? .leading : .trailing)
            ),
            removal: .modifier(
                active: CubeFace(angle: -90 * sign, offset: -width * sign, anchor: forward ? .trailing : .leading),
                identity: CubeFace(angle: 0, offset: 0, anchor: forward ? .trailing : .leading)
            )
        )
    }
}
