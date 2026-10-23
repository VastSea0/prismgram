import SwiftUI
import AppKit
import Observation
import WebKit

@MainActor
@Observable
final class AppStore {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum Session: Equatable {
        case unknown
        case signedOut
        case signedIn
    }

    struct RequestFailure: Error {
        let message: String
    }

    struct WebPageRequest: Identifiable {
        let id = UUID()
        let url: URL
        var title: String?
    }

    /// One paginated grid of posts.
    struct PostPage {
        var items: [IGPost] = []
        var phase: Phase = .idle
        var cursor: String?
        var isLoadingMore = false
    }

    let client: any InstagramTransport
    let api: InstagramAPI

    // Session
    private(set) var session: Session = .unknown
    private(set) var viewerID: String?
    private(set) var viewerUsername: String?

    // Navigation / presentation
    /// `PRISMGRAM_LAYOUT=phone|hybrid|desktop` overrides the saved launch layout for one run (handy for testing).
    var layoutMode: AppLayoutMode = AppLayoutMode(
        rawValue: ProcessInfo.processInfo.environment["PRISMGRAM_LAYOUT"]
            ?? UserDefaults.standard.string(forKey: Preference.launchLayout) ?? ""
    ) ?? .hybrid {
        didSet {
            guard oldValue != layoutMode else { return }
            isInspectorShown = layoutMode == .desktop
        }
    }
    /// `PRISMGRAM_TAB=<tab>` picks the first tab for one run (handy for testing).
    private(set) var tab: InstagramTab = InstagramTab(rawValue: ProcessInfo.processInfo.environment["PRISMGRAM_TAB"] ?? "") ?? .home
    var isInspectorShown = false
    var profileUserID: String?
    var profileUsername: String?
    var storyViewer: IGStoryTray?
    /// The trays the open story viewer moves through (the home tray or a profile's highlights).
    private(set) var storyQueue: [IGStoryTray] = []
    private var loadingStoryIDs: Set<String> = []
    var detailPost: IGPost?
    var sharePost: IGPost?
    var isShowingLogin = false
    var isShowingInstagramSettings = false

    // Data
    private(set) var stories: [IGStoryTray] = []
    private(set) var feed: [IGPost] = []
    private(set) var feedPhase: Phase = .idle
    private(set) var isLoadingMoreFeed = false
    private var feedCursor: String?

    private(set) var explore: [IGPost] = []
    private(set) var explorePhase: Phase = .idle

    private(set) var reels: [IGPost] = []
    private(set) var reelsPhase: Phase = .idle
    private var reelsCursor: String?
    private var isLoadingMoreReels = false

    private(set) var activity: [IGActivity] = []
    private(set) var activityPhase: Phase = .idle

    private(set) var notes: [IGNote] = []
    var openNote: IGNote?
    var isComposingNote = false
    private(set) var directThreads: [IGDirectThread] = []
    private(set) var directPhase: Phase = .idle
    var selectedThreadID: String?
    private(set) var isSendingDirectMessage = false
    private var sendChain: Task<Void, Never>?
    private var loadingOlderThreadIDs: Set<String> = []
    /// A short message shown over the conversation when an action could not be completed.
    var directNotice: String?
    /// An instagram.com page shown in the in-app browser sheet (settings, shared links).
    var webPage: WebPageRequest?

    private(set) var profile: IGUser?
    private(set) var profileGrids: [ProfileSection: PostPage] = [:]
    var profileSection: ProfileSection = .posts
    private(set) var profileHighlights: [IGStoryTray] = []
    private(set) var profilePhase: Phase = .idle
    /// Other people's profiles opened on top of each other, newest last; Back walks down this stack.
    private(set) var profileStack: [IGUser] = []
    private var profileReturnTab: InstagramTab?
    private var profileToken = UUID()
    /// While the hidden page is opening a profile: whose (lowercased username), and what its queries delivered.
    private var pageProfileTarget: String?
    private var pageProfileUser: IGUser?
    /// The profile grid the hidden page is currently feeding.
    private var capture: ProfileSection?
    /// Set when "Message" is pressed on a profile with no existing chat, so the inbox opens filtered to that person.
    var pendingDirectSearch: String?

    var profilePosts: [IGPost] { profileGrids[.posts]?.items ?? [] }
    var isViewingOtherProfile: Bool { profileUserID != nil }

    init(client: any InstagramTransport = InstagramClient()) {
        self.client = client
        self.api = InstagramAPI(transport: client)
        client.onNetworkEvent = { [weak self] event in
            self?.handleNetworkEvent(event)
        }
    }

    // MARK: Session

    func bootstrap() async {
        guard let id = await client.viewerID() else {
            session = .signedOut
            return
        }
        viewerID = id
        await client.prepare()
        client.setNetworkTap(pattern: "/api/|/graphql")
        if let detected = await client.detectViewerUsername() {
            viewerUsername = detected
        }
        session = .signedIn
    }

    func didSignIn() async {
        isShowingLogin = false
        resetData()
        await bootstrap()
    }

    private func resetData() {
        stories = []; feed = []; feedPhase = .idle; feedCursor = nil
        explore = []; explorePhase = .idle
        reels = []; reelsPhase = .idle
        activity = []; activityPhase = .idle
        notes = []; directThreads = []; directPhase = .idle; selectedThreadID = nil
        profile = nil; profileGrids = [:]; profileHighlights = []; profilePhase = .idle
        profileStack = []; profileReturnTab = nil; profileUserID = nil; profileUsername = nil
    }

    // MARK: Network Tap Handling

    private func handleNetworkEvent(_ event: InstagramClient.NetworkEvent) {
        guard (200..<300).contains(event.status),
              let data = event.body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let opName = event.label.components(separatedBy: " #").first ?? ""
        InstagramClient.debugLog("tap: \(event.method) \(event.url) label=\(event.label.isEmpty ? "-" : event.label)")
        if SchemaDump.folder != nil, !opName.isEmpty {
            SchemaDump.write(json, name: opName)
        }

        switch opName {
        case "IGDInboxTrayQuery", "PolarisProfileNoteBubbleQuery":
            let parsed = IGJSON.notes(from: json)
            if !parsed.isEmpty {
                notes = parsed
                if let own = parsed.first(where: { $0.user.id == viewerID }) {
                    viewerUsername = own.user.username
                }
            }

        // The inbox arrives under several names depending on what the page is doing; all carry the same mailbox shape.
        // Only mark directPhase = .loaded when the query actually carries message previews (PolarisDirectInboxQuery)
        // so background badge/jewel queries at boot don't short-circuit loadDirect().
        case "PolarisDirectInboxQuery", "IGDChatTabsJewelOffMsysQuery", "IGDBadgeCountOffMsysQuery":
            let parsed = IGJSON.directThreads(from: json)
            if !parsed.isEmpty {
                mergeThreads(parsed)
                if selectedThreadID == nil {
                    selectedThreadID = directThreads.first?.id
                }
                if opName == "PolarisDirectInboxQuery" || parsed.contains(where: { !$0.messages.isEmpty || !$0.snippet.isEmpty }) {
                    directPhase = .loaded
                }
            } else if directPhase == .loading && opName == "PolarisDirectInboxQuery" {
                directPhase = .loaded
            }

        case "PolarisProfilePageContentQuery":
            if let target = pageProfileTarget,
               let userDict = (json["data"] as? [String: Any])?["user"] as? [String: Any],
               let user = IGJSON.user(userDict), user.username.lowercased() == target {
                pageProfileUser = user
            }

        case "PolarisProfilePostsQuery":
            if let target = pageProfileTarget, capture == .posts,
               let connection = (json["data"] as? [String: Any])?["xdt_api__v1__feed__user_timeline_graphql_connection"] as? [String: Any] {
                let edges = (connection["edges"] as? [[String: Any]]) ?? []
                let posts = edges.compactMap { ($0["node"] as? [String: Any]).flatMap(IGJSON.post) }
                if posts.allSatisfy({ $0.user.username.lowercased() == target }) {
                    let hasMore = IGJSON.bool((connection["page_info"] as? [String: Any])?["has_next_page"])
                    receiveProfilePosts(posts, for: .posts, hasMore: hasMore)
                }
            }

        case "PolarisProfileStoryHighlightsTrayContentQuery":
            if pageProfileTarget != nil, let owner = profile {
                let parsed = IGJSON.highlights(from: json, fallbackUser: owner).filter { $0.user.id == owner.id }
                if !parsed.isEmpty { profileHighlights = parsed }
            }

        case "IGDThreadDetailQuery",
             "IGDMessageListOffMsysQuery",
             "IGDMessageListAnchorMessageRangeBeforeOffMsysQuery",
             "IGDMessageListAnchorMessageRangeAfterOffMsysQuery":
            if let detailed = IGJSON.directThreadDetail(
                from: json,
                fallbackThread: selectedThread,
                viewerID: viewerID ?? ""
            ) {
                mergeDetailedThread(detailed)
            }

        case "PolarisFeedTimelineRootV2Query", "PolarisFeedTimelineQuery":
            let posts = IGJSON.collectPosts(in: json)
            if !posts.isEmpty {
                let known = Set(feed.map(\.id))
                let fresh = posts.filter { !known.contains($0.id) }
                if !fresh.isEmpty {
                    feed += fresh
                    if feedPhase != .loaded { feedPhase = .loaded }
                }
            }

        default:
            if let section = capture, section != .posts, pageProfileTarget != nil,
               !opName.contains("Ads"), !opName.contains("Suggested") {
                let posts = IGJSON.collectPosts(in: json)
                if !posts.isEmpty { receiveProfilePosts(posts, for: section, hasMore: nil) }
            }
            if event.url.contains("reels_media") {
                for trayID in loadingStoryIDs {
                    let slides = IGJSON.storySlides(from: json, reelID: trayID)
                    if !slides.isEmpty {
                        applyStorySlides(slides, for: trayID)
                    }
                }
            }
        }
    }

    private func mergeThreads(_ incoming: [IGDirectThread]) {
        var existingByID: [String: IGDirectThread] = Dictionary(uniqueKeysWithValues: directThreads.map { ($0.id, $0) })
        var ordered: [IGDirectThread] = []
        for var item in incoming {
            if let prev = existingByID[item.id] ?? directThreads.first(where: { $0.threadFBID == item.threadFBID }) {
                if item.messages.count < prev.messages.count {
                    item.messages = prev.messages
                    item.hasOlderMessages = prev.hasOlderMessages
                }
            }
            ordered.append(item)
            existingByID.removeValue(forKey: item.id)
        }
        directThreads = ordered
    }

    private func mergeDetailedThread(_ detailed: IGDirectThread) {
        if let idx = directThreads.firstIndex(where: { $0.id == detailed.id || $0.threadFBID == detailed.threadFBID }) {
            var updated = directThreads[idx]
            if !detailed.messages.isEmpty {
                // Keep messages still being sent, or that failed, until the server's copy replaces them.
                let local = updated.messages.filter { $0.delivery != .sent && $0.id.hasPrefix("local-") }
                let existingSent = updated.messages.filter { !$0.id.hasPrefix("local-") }
                var byID: [String: IGDirectMessage] = Dictionary(uniqueKeysWithValues: existingSent.map { ($0.id, $0) })
                for msg in detailed.messages {
                    byID[msg.id] = msg
                }
                let mergedSent = byID.values.sorted { $0.timestamp < $1.timestamp }
                let confirmed = Set(detailed.messages.filter(\.isFromViewer).map(\.text))
                updated.messages = mergedSent + local.filter { $0.delivery == .failed || !confirmed.contains($0.text) }
            }
            updated.hasOlderMessages = detailed.hasOlderMessages
            if !detailed.snippet.isEmpty {
                updated.snippet = detailed.snippet
            }
            directThreads[idx] = updated
        } else {
            directThreads.append(detailed)
        }
    }

    // MARK: Navigation

    func select(_ newTab: InstagramTab) {
        haptic(.alignment)
        withAnimation(.snappy(duration: 0.25)) {
            if newTab == .profile && (tab != .profile || isViewingOtherProfile) {
                showOwnProfile()
            }
            tab = newTab
        }
    }

    private func showOwnProfile() {
        guard isViewingOtherProfile || profile == nil || profile?.id != viewerID else { return }
        profileStack = []
        profileReturnTab = nil
        profileUserID = nil
        profileUsername = nil
        resetProfileContent(placeholder: nil)
    }

    private func resetProfileContent(placeholder: IGUser?) {
        profileToken = UUID()
        pageProfileTarget = nil
        pageProfileUser = nil
        capture = nil
        profile = placeholder
        profileGrids = [:]
        profileHighlights = []
        profileSection = .posts
        profilePhase = .idle
    }

    func openProfile(of user: IGUser) {
        detailPost = nil
        if storyViewer != nil { closeStory() }
        if user.id == viewerID {
            if tab != .profile { profileReturnTab = tab }
            showOwnProfile()
            withAnimation(.snappy(duration: 0.25)) { tab = .profile }
            Task { await ensureLoaded(.profile) }
            return
        }
        guard profile?.id != user.id || tab != .profile else { return }
        if tab != .profile {
            profileReturnTab = tab
            profileStack = []
        } else if let current = profile, current.id != viewerID {
            profileStack.append(current)
        }
        profileUserID = user.id
        profileUsername = user.username
        resetProfileContent(placeholder: user)
        withAnimation(.snappy(duration: 0.25)) { tab = .profile }
        Task { await loadProfile() }
    }

    /// Back from someone's profile: to the profile opened before it, or to the tab it was opened from.
    func closeOtherProfile() {
        if let previous = profileStack.popLast() {
            profileUserID = previous.id
            profileUsername = previous.username
            resetProfileContent(placeholder: previous)
            Task { await loadProfile() }
            return
        }
        let destination = profileReturnTab
        profileReturnTab = nil
        profileUserID = nil
        profileUsername = nil
        resetProfileContent(placeholder: nil)
        if let destination, destination != .profile {
            withAnimation(.snappy(duration: 0.25)) { tab = destination }
        } else {
            Task { await loadProfile() }
        }
    }

    var canGoBack: Bool { tab == .profile && isViewingOtherProfile }

    func ensureLoaded(_ tab: InstagramTab) async {
        guard session == .signedIn else { return }
        switch tab {
        case .home:
            if feedPhase == .idle { await loadHome() }
        case .explore:
            if explorePhase == .idle { await loadExplore() }
        case .reels:
            if reelsPhase == .idle { await loadReels() }
        case .activity:
            if activityPhase == .idle { await loadActivity() }
        case .direct:
            if directPhase == .idle { await loadDirect() }
        case .profile:
            if profilePhase == .idle { await loadProfile() }
        }
    }

    func refresh(_ tab: InstagramTab) async {
        haptic(.alignment)
        switch tab {
        case .home: feedCursor = nil; await loadHome()
        case .explore: await loadExplore()
        case .reels: await loadReels()
        case .activity: await loadActivity()
        case .direct: await loadDirect()
        case .profile: await loadProfile()
        }
    }

    // MARK: Requests

    /// Runs an `InstagramAPI` call and signs the user out if the session has expired.
    private func run<T>(_ operation: (InstagramAPI) async throws -> T) async throws -> T {
        do {
            return try await operation(api)
        } catch InstagramAPI.Failure.unauthorized {
            session = .signedOut
            throw RequestFailure(message: "Oturum süresi doldu. Yeniden giriş yapın.")
        } catch InstagramAPI.Failure.rejected(let reason) {
            throw RequestFailure(message: reason)
        }
    }

    private func message(for error: Error) -> String {
        (error as? RequestFailure)?.message ?? "Beklenmeyen bir hata oluştu."
    }

    // MARK: Loaders

    func loadHome() async {
        guard feedPhase != .loading else { return }
        feedPhase = .loading
        do {
            if let loadedTray = try? await run({ try await $0.reelsTray() }) {
                var mergedTray = loadedTray
                if let vid = viewerID, !mergedTray.contains(where: { $0.user.id == vid }) {
                    if let ownSlides = try? await run({ try await $0.reelsMedia(reelID: vid) }), !ownSlides.isEmpty {
                        let ownUser = viewer ?? IGUser(
                            id: vid,
                            username: viewerUsername ?? "Hikayen",
                            fullName: "",
                            avatarURL: nil,
                            isVerified: false
                        )
                        let own = IGStoryTray(
                            id: vid,
                            user: ownUser,
                            hasUnseen: false,
                            slides: ownSlides
                        )
                        mergedTray.insert(own, at: 0)
                    }
                }
                stories = mergedTray
                if let ownTray = stories.first(where: { $0.user.id == viewerID }) {
                    viewerUsername = ownTray.user.username
                }
            }
            let page = try await run { try await $0.timeline() }
            feed = page.posts
            feedCursor = page.nextCursor
            feedPhase = .loaded
            // The first answer is often a small "shell" of the feed; keep asking until there is enough to scroll.
            var rounds = 0
            while feed.count < 8, feedCursor != nil, rounds < 4 {
                rounds += 1
                await loadMoreFeed()
            }
            if viewerUsername == nil, let detected = await client.detectViewerUsername() {
                viewerUsername = detected
            }
        } catch {
            feedPhase = .failed(message(for: error))
        }
    }

    func loadMoreFeed() async {
        guard let cursor = feedCursor, !isLoadingMoreFeed, feedPhase == .loaded else { return }
        isLoadingMoreFeed = true
        defer { isLoadingMoreFeed = false }
        do {
            let page = try await run { try await $0.timeline(cursor: cursor) }
            let known = Set(feed.map(\.id))
            feed += page.posts.filter { !known.contains($0.id) }
            feedCursor = page.nextCursor
        } catch {
            feedCursor = nil
        }
    }

    // MARK: Stories (own + other people's stories + highlights)

    func openStory(_ tray: IGStoryTray, in queue: [IGStoryTray]? = nil) {
        storyQueue = queue ?? [tray]
        withAnimation(.spring(duration: 0.38, bounce: 0.12)) {
            storyViewer = latest(tray)
        }
        prepareStory(tray)
    }

    func closeStory() {
        if let current = storyViewer { markStorySeen(current.id) }
        withAnimation(.spring(duration: 0.32, bounce: 0)) {
            storyViewer = nil
        }
        storyQueue = []
    }

    /// The tray before (`-1`) or after (`+1`) the open one in the queue, if any.
    func adjacentStory(_ delta: Int) -> IGStoryTray? {
        guard let current = storyViewer,
              let index = storyQueue.firstIndex(where: { $0.id == current.id }) else { return nil }
        return storyQueue[safe: index + delta].map(latest)
    }

    /// Moves the viewer to the neighbouring tray; closes it when there is none.
    func showAdjacentStory(_ delta: Int) {
        guard let next = adjacentStory(delta) else {
            if delta > 0 { closeStory() }
            return
        }
        if let current = storyViewer { markStorySeen(current.id) }
        storyViewer = next
        prepareStory(next)
    }

    private func prepareStory(_ tray: IGStoryTray) {
        let current = latest(tray)
        let isOwn = tray.user.id == viewerID || (viewerUsername != nil && tray.user.username == viewerUsername)
        if current.slides.isEmpty || (isOwn && current.slides.contains(where: { $0.viewerCount == nil || $0.viewers.isEmpty })) {
            Task { await loadStorySlides(for: tray) }
        }
        // Load the next person's story while this one plays, so moving on does not show a spinner.
        if let index = storyQueue.firstIndex(where: { $0.id == tray.id }),
           let following = storyQueue[safe: index + 1], latest(following).slides.isEmpty {
            Task { await loadStorySlides(for: following) }
        }
    }

    /// The freshest copy of a tray: the tray lists are where slides land after loading.
    private func latest(_ tray: IGStoryTray) -> IGStoryTray {
        if let current = storyViewer, current.id == tray.id, !current.slides.isEmpty { return current }
        return stories.first(where: { $0.id == tray.id && !$0.slides.isEmpty })
            ?? profileHighlights.first(where: { $0.id == tray.id && !$0.slides.isEmpty })
            ?? storyQueue.first(where: { $0.id == tray.id && !$0.slides.isEmpty })
            ?? tray
    }

    func isLoadingStory(_ id: String) -> Bool { loadingStoryIDs.contains(id) }

    func loadStorySlides(for tray: IGStoryTray) async {
        guard loadingStoryIDs.insert(tray.id).inserted else { return }
        defer { loadingStoryIDs.remove(tray.id) }

        do {
            let slides = try await run { try await $0.reelsMedia(reelID: tray.id) }
            if !slides.isEmpty {
                applyStorySlides(slides, for: tray.id)
                return
            }
        } catch {
            // Fall back to driving the hidden page to the story route so its own fetch is tapped.
        }

        guard !tray.id.hasPrefix("highlight:") else { return }
        await client.withPage("story \(tray.id)") {
            guard latest(tray).slides.isEmpty else { return }
            _ = await client.navigate(to: "/stories/\(tray.user.username)/")
            for _ in 0..<12 {
                try? await Task.sleep(for: .milliseconds(350))
                if !latest(tray).slides.isEmpty { break }
            }
        }
    }

    private func applyStorySlides(_ slides: [IGMediaItem], for trayID: String) {
        func mergeSlides(_ existing: [IGMediaItem], with incoming: [IGMediaItem]) -> [IGMediaItem] {
            let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
            return incoming.map { slide in
                guard let prev = byID[slide.id] else { return slide }
                var merged = slide
                if merged.viewerCount == nil { merged.viewerCount = prev.viewerCount }
                if merged.viewers.isEmpty { merged.viewers = prev.viewers }
                if merged.likedViewerIDs.isEmpty { merged.likedViewerIDs = prev.likedViewerIDs }
                return merged
            }
        }
        if let index = stories.firstIndex(where: { $0.id == trayID }) {
            stories[index].slides = mergeSlides(stories[index].slides, with: slides)
        }
        if let index = profileHighlights.firstIndex(where: { $0.id == trayID }) {
            profileHighlights[index].slides = mergeSlides(profileHighlights[index].slides, with: slides)
        }
        if let index = storyQueue.firstIndex(where: { $0.id == trayID }) {
            storyQueue[index].slides = mergeSlides(storyQueue[index].slides, with: slides)
        }
        if var current = storyViewer, current.id == trayID {
            current.slides = mergeSlides(current.slides, with: slides)
            storyViewer = current
        }
    }

    /// Loads the full viewer list and viewer count for a story slide (`list_reel_media_viewer`).
    func loadStoryViewers(trayID: String, slideID: String) async {
        do {
            let result = try await run { try await $0.storyViewers(mediaID: slideID) }
            updateStorySlide(trayID: trayID, slideID: slideID) { slide in
                if !result.users.isEmpty {
                    var seen = Set(result.users.map(\.id))
                    var combined = result.users
                    for existing in slide.viewers where seen.insert(existing.id).inserted {
                        combined.append(existing)
                    }
                    slide.viewers = combined
                }
                slide.likedViewerIDs.formUnion(result.likedIDs)
                if let count = result.count {
                    slide.viewerCount = max(count, slide.viewers.count)
                } else if slide.viewerCount == nil {
                    slide.viewerCount = slide.viewers.count
                }
            }
        } catch {
            // Fallback: refresh the reel via `reels_media` if `list_reel_media_viewer` was unavailable.
            if let slides = try? await run({ try await $0.reelsMedia(reelID: trayID) }), !slides.isEmpty {
                applyStorySlides(slides, for: trayID)
            }
        }
    }

    private func updateStorySlide(trayID: String, slideID: String, _ change: (inout IGMediaItem) -> Void) {
        func apply(to tray: inout IGStoryTray) {
            guard tray.id == trayID else { return }
            let pk = slideID.split(separator: "_").first.map(String.init) ?? slideID
            if let idx = tray.slides.firstIndex(where: { $0.id == slideID || $0.id.hasPrefix(pk) }) {
                change(&tray.slides[idx])
            }
        }
        for i in stories.indices { apply(to: &stories[i]) }
        for i in profileHighlights.indices { apply(to: &profileHighlights[i]) }
        for i in storyQueue.indices { apply(to: &storyQueue[i]) }
        if var current = storyViewer, current.id == trayID {
            apply(to: &current)
            storyViewer = current
        }
    }

    /// Sends a story reply (or direct message) to the story's author.
    func replyToStory(_ tray: IGStoryTray, slide: IGMediaItem, text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        haptic(.levelChange)
        let pk = slide.id.split(separator: "_").first.map(String.init) ?? slide.id
        if let thread = directThreads.first(where: { !$0.isGroup && $0.users.first?.id == tray.user.id }) {
            for id in Set([thread.id, thread.threadFBID]) where !id.isEmpty {
                if await broadcast(kind: "reel_share", fields: [
                    "thread_ids": "[\"\(id)\"]",
                    "media_id": pk,
                    "text": trimmed,
                    "entry": "reel"
                ]) != nil {
                    return true
                }
            }
            return await deliver(text: trimmed, to: thread)
        }
        if await broadcast(kind: "reel_share", fields: [
            "recipient_users": "[[\(tray.user.id)]]",
            "media_id": pk,
            "text": trimmed,
            "entry": "reel"
        ]) != nil {
            return true
        }
        return await broadcast(kind: "text", fields: [
            "recipient_users": "[[\(tray.user.id)]]",
            "text": trimmed
        ]) != nil
    }

    func loadExplore() async {
        guard explorePhase != .loading else { return }
        explorePhase = .loading
        do {
            explore = try await run { try await $0.exploreGrid() }
            explorePhase = .loaded
        } catch {
            explorePhase = .failed(message(for: error))
        }
    }

    func loadReels() async {
        guard reelsPhase != .loading else { return }
        reelsPhase = .loading
        do {
            let page = try await run { try await $0.clipsDiscover() }
            reels = page.videos
            reelsCursor = page.nextCursor
            reelsPhase = .loaded
        } catch {
            reelsPhase = .failed(message(for: error))
        }
    }

    func loadMoreReels() async {
        guard let cursor = reelsCursor, !isLoadingMoreReels, reelsPhase == .loaded else { return }
        isLoadingMoreReels = true
        defer { isLoadingMoreReels = false }
        do {
            let page = try await run { try await $0.clipsDiscover(cursor: cursor) }
            let known = Set(reels.map(\.id))
            reels += page.videos.filter { !known.contains($0.id) }
            reelsCursor = page.nextCursor
        } catch {
            reelsCursor = nil
        }
    }

    struct SearchResults {
        struct Hashtag { let name: String; let mediaCount: Int }
        var users: [IGUser] = []
        var hashtags: [Hashtag] = []
    }

    /// Instagram's blended search: accounts first, then hashtags.
    func search(_ query: String) async -> SearchResults {
        guard let decoded = try? await run({ try await $0.topSearch(query: query) }) else {
            return SearchResults()
        }
        return SearchResults(users: decoded.parsedUsers, hashtags: decoded.parsedHashtags)
    }

    func loadActivity() async {
        guard activityPhase != .loading else { return }
        activityPhase = .loading
        do {
            activity = try await run { try await $0.newsInbox() }
            activityPhase = .loaded
        } catch {
            activityPhase = .failed(message(for: error))
        }
    }

    // MARK: Direct Messages & Notes

    func loadDirect() async {
        guard directPhase != .loading else { return }
        directPhase = .loading
        let loaded = await client.withPage("direct inbox") { () async -> Bool in
            _ = await client.navigate(to: "/direct/inbox/")
            for _ in 0..<24 {
                try? await Task.sleep(for: .milliseconds(400))
                if directPhase == .loaded { return true }
            }
            return !directThreads.isEmpty
        }
        if loaded {
            directPhase = .loaded
            return
        }
        if directPhase == .loading {
            directPhase = directThreads.isEmpty ? .failed("Mesaj kutusu yüklenemedi. Yeniden deneyin.") : .loaded
        }
    }

    var selectedThread: IGDirectThread? {
        guard let id = selectedThreadID else { return directThreads.first }
        return directThreads.first(where: { $0.id == id }) ?? directThreads.first
    }

    func selectThread(_ thread: IGDirectThread) {
        selectedThreadID = thread.id
        if let idx = directThreads.firstIndex(where: { $0.id == thread.id }) {
            directThreads[idx].isUnread = false
        }
        Task {
            // Opening it in the hidden page is what loads its messages (tapped IGDThreadDetailQuery).
            await client.withPage("open thread") {
                _ = await client.openDirectThread(ids: [thread.threadFBID, thread.id])
            }
        }
    }

    func isLoadingOlderMessages(in thread: IGDirectThread) -> Bool {
        loadingOlderThreadIDs.contains(thread.id)
    }

    /// Scrolls the hidden thread view to its top boundary so Relay fetches the previous page of messages.
    func loadOlderMessages(in thread: IGDirectThread) async {
        guard thread.hasOlderMessages, !loadingOlderThreadIDs.contains(thread.id) else { return }
        loadingOlderThreadIDs.insert(thread.id)
        defer { loadingOlderThreadIDs.remove(thread.id) }

        let beforeCount = directThreads.first(where: { $0.id == thread.id })?.messages.count ?? thread.messages.count
        await client.withPage("load older messages") {
            guard await client.openDirectThread(ids: [thread.threadFBID, thread.id]) != nil else { return }
            _ = await client.scrollDirectThreadToTop()
            for attempt in 0..<14 {
                try? await Task.sleep(for: .milliseconds(250))
                let currentCount = directThreads.first(where: { $0.id == thread.id })?.messages.count ?? 0
                if currentCount > beforeCount { break }
                if attempt == 5 {
                    _ = await client.scrollDirectThreadToTop()
                }
            }
        }
    }

    /// Shows the message in the transcript at once (Apple's "Sending…" state) and sends queued messages one after another.
    func sendDirectMessage(text: String, in thread: IGDirectThread) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = directThreads.firstIndex(where: { $0.id == thread.id }) else { return }
        let message = IGDirectMessage(
            id: "local-\(UUID().uuidString)",
            senderFBID: thread.viewerFBID,
            senderUsername: viewerUsername,
            senderAvatarURL: nil,
            text: trimmed,
            timestamp: .now,
            isFromViewer: true,
            delivery: .sending
        )
        withAnimation(.spring(duration: 0.35, bounce: 0.18)) {
            directThreads[index].messages.append(message)
            directThreads[index].snippet = trimmed
            directThreads[index].lastActivityAt = .now
            // Apple Messages moves the conversation to the top of the list as soon as you send.
            let updated = directThreads.remove(at: index)
            directThreads.insert(updated, at: directThreads.firstIndex(where: { !$0.isPinned }) ?? 0)
        }
        enqueueSend(message, threadID: thread.id)
    }

    func retryDirectMessage(_ message: IGDirectMessage, in thread: IGDirectThread) {
        setDelivery(.sending, for: message.id, in: thread.id)
        enqueueSend(message, threadID: thread.id)
    }

    private func enqueueSend(_ message: IGDirectMessage, threadID: String) {
        let previous = sendChain
        sendChain = Task {
            await previous?.value
            guard let thread = directThreads.first(where: { $0.id == threadID }) else { return }
            isSendingDirectMessage = true
            defer { isSendingDirectMessage = false }
            let sent = await deliver(text: message.text, to: thread)
            setDelivery(sent ? .sent : .failed, for: message.id, in: threadID)
        }
    }

    /// Sends text to exactly this conversation. The recipient is always addressed by id; if that cannot
    /// be guaranteed the message is reported as failed rather than risk it reaching someone else.
    private func deliver(text: String, to thread: IGDirectThread) async -> Bool {
        for id in Set([thread.id, thread.threadFBID]) where !id.isEmpty {
            if await broadcast(kind: "text", fields: ["thread_ids": "[\"\(id)\"]", "text": text]) != nil {
                return true
            }
        }
        return await client.withPage("send message") {
            guard let pathID = await client.openDirectThread(ids: [thread.threadFBID, thread.id]) else { return false }
            return await client.sendDirectMessage(text: text, threadPathID: pathID)
        }
    }

    /// Calls a `direct_v2/threads/broadcast/<kind>/` endpoint and returns its payload when Instagram answers `ok`.
    /// Uses the transport directly so that an unsupported endpoint can never sign the user out.
    func broadcast(kind: String, fields: [String: String]) async -> [String: Any]? {
        await api.broadcast(kind: kind, fields: fields)
    }

    private func setDelivery(_ delivery: IGDirectMessage.Delivery, for messageID: String, in threadID: String) {
        guard let threadIndex = directThreads.firstIndex(where: { $0.id == threadID }),
              let messageIndex = directThreads[threadIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }
        directThreads[threadIndex].messages[messageIndex].delivery = delivery
    }

    /// Leaves an emoji reaction. Uses the direct_v2 API when the message's item id is known, otherwise the
    /// hidden page's own reaction control in the verified thread. Rolled back if neither works.
    func react(_ emoji: String, to message: IGDirectMessage, in thread: IGDirectThread) {
        haptic(.levelChange)
        updateMessage(message.id, in: thread.id) { $0.reactions = [emoji] + $0.reactions.filter { $0 != emoji } }
        let previous = message.reactions
        let chain = sendChain
        sendChain = Task {
            await chain?.value
            var done = false
            if let itemID = message.itemID {
                for id in Set([thread.id, thread.threadFBID]) where !done && !id.isEmpty {
                    done = await broadcast(kind: "reaction", fields: [
                        "thread_ids": "[\"\(id)\"]",
                        "item_id": itemID,
                        "node_type": "item",
                        "reaction_status": "created",
                        "reaction_type": "like",
                        "emoji": emoji
                    ]) != nil
                }
            }
            if !done, !message.text.isEmpty {
                done = await client.withPage("react") {
                    guard let pathID = await client.openDirectThread(ids: [thread.threadFBID, thread.id]) else { return false }
                    return await client.performMessageAction("react", messageText: message.text, emoji: emoji, threadPathID: pathID)
                }
            }
            if !done {
                updateMessage(message.id, in: thread.id) { $0.reactions = previous }
                withAnimation { directNotice = "İfade gönderilemedi" }
            }
        }
    }

    /// Replies to a message. The reply appears at once; it is only sent as a real reply, never as plain text.
    func sendReply(text: String, to target: IGDirectMessage, in thread: IGDirectThread) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = directThreads.firstIndex(where: { $0.id == thread.id }) else { return }
        let message = IGDirectMessage(
            id: "local-\(UUID().uuidString)",
            senderFBID: thread.viewerFBID,
            senderUsername: viewerUsername,
            senderAvatarURL: nil,
            text: trimmed,
            timestamp: .now,
            isFromViewer: true,
            delivery: .sending,
            replyTo: IGDirectMessage.ReplyQuote(
                text: target.text.isEmpty ? target.kind.label : target.text,
                senderUsername: target.senderUsername,
                isFromViewer: target.isFromViewer
            )
        )
        withAnimation(.spring(duration: 0.35, bounce: 0.18)) {
            directThreads[index].messages.append(message)
            directThreads[index].snippet = trimmed
            directThreads[index].lastActivityAt = .now
        }
        let chain = sendChain
        sendChain = Task {
            await chain?.value
            isSendingDirectMessage = true
            defer { isSendingDirectMessage = false }
            var sent = false
            if let itemID = target.itemID {
                for id in Set([thread.id, thread.threadFBID]) where !sent && !id.isEmpty {
                    sent = await broadcast(kind: "text", fields: [
                        "thread_ids": "[\"\(id)\"]",
                        "text": trimmed,
                        "replied_to_item_id": itemID
                    ]) != nil
                }
            }
            if !sent, !target.text.isEmpty {
                sent = await client.withPage("reply") {
                    guard let pathID = await client.openDirectThread(ids: [thread.threadFBID, thread.id]),
                          await client.performMessageAction("reply", messageText: target.text, emoji: nil, threadPathID: pathID) else { return false }
                    try? await Task.sleep(for: .milliseconds(250))
                    return await client.sendDirectMessage(text: trimmed, threadPathID: pathID)
                }
            }
            setDelivery(sent ? .sent : .failed, for: message.id, in: thread.id)
            if !sent { withAnimation { directNotice = "Yanıt gönderilemedi" } }
        }
    }

    private func updateMessage(_ id: String, in threadID: String, _ change: (inout IGDirectMessage) -> Void) {
        guard let t = directThreads.firstIndex(where: { $0.id == threadID }),
              let m = directThreads[t].messages.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.spring(duration: 0.3, bounce: 0.4)) { change(&directThreads[t].messages[m]) }
    }

    private func haptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard UserDefaults.standard.object(forKey: Preference.haptics) as? Bool ?? true else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
    }

    // MARK: Account

    /// Forgets the Instagram session on this Mac and returns to the sign-in screen.
    func signOut() async {
        await api.logout()
        let store = WKWebsiteDataStore.default()
        let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        await store.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            for: records.filter { $0.displayName.lowercased().contains("instagram") || $0.displayName.lowercased().contains("facebook") }
        )
        resetData()
        viewerID = nil
        viewerUsername = nil
        tab = .home
        session = .signedOut
    }

    func setAccountPrivate(_ makePrivate: Bool) async -> Bool {
        guard await api.setPrivacy(isPrivate: makePrivate) else { return false }
        updateProfile(viewerID ?? "") { $0.isPrivate = makePrivate }
        return true
    }

    func reloadEngine() async {
        await client.prepare()
        client.setNetworkTap(pattern: "/api/|/graphql")
        resetData()
        await ensureLoaded(tab)
    }

    // MARK: Notes

    /// The viewer as far as any loaded response knows them (for their own avatar in notes and comments).
    var viewer: IGUser? {
        if let profile, profile.id == viewerID { return profile }
        return stories.first(where: { $0.user.id == viewerID })?.user
            ?? notes.first(where: { $0.user.id == viewerID })?.user
            ?? feed.first(where: { $0.user.id == viewerID })?.user
    }

    var ownNote: IGNote? { notes.first(where: { $0.user.id == viewerID }) }

    /// Answers a note the way Instagram does: as a direct message to its author.
    func replyToNote(_ note: IGNote, text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if let thread = directThreads.first(where: { !$0.isGroup && $0.users.first?.id == note.user.id }) {
            return await deliver(text: trimmed, to: thread)
        }
        return await broadcast(kind: "text", fields: ["recipient_users": "[[\(note.user.id)]]", "text": trimmed]) != nil
    }

    /// Shares a note (60 characters) with mutual followers (`audience` 0) or close friends (1).
    func createNote(text: String, closeFriends: Bool) async -> Bool {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard !trimmed.isEmpty,
              let created = await api.createNote(text: trimmed, closeFriends: closeFriends) else { return false }
        if let me = viewer {
            let note = IGNote(
                id: "own-\(UUID().uuidString)",
                user: me,
                text: trimmed,
                musicTitle: nil,
                musicArtist: nil,
                createdAt: .now,
                noteID: created.note?.id?.value
            )
            withAnimation(.snappy) { notes = [note] + notes.filter { $0.user.id != viewerID } }
        }
        return true
    }

    func deleteOwnNote() async -> Bool {
        guard let note = ownNote, let noteID = note.noteID,
              await api.deleteNote(id: noteID) else { return false }
        withAnimation(.snappy) { notes.removeAll { $0.id == note.id } }
        return true
    }

    /// Opens Instagram pages inside the app with the signed-in session; other sites go to the browser.
    func openWeb(_ url: URL, title: String? = nil) {
        if let host = url.host?.lowercased(), host.hasSuffix("instagram.com") {
            webPage = WebPageRequest(url: url, title: title)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func markThreadRead(_ thread: IGDirectThread, _ isRead: Bool = true) {
        if let index = directThreads.firstIndex(where: { $0.id == thread.id }) {
            directThreads[index].isUnread = !isRead
        }
    }

    // MARK: Profile

    /// Loads a profile the way instagram.com does: the hidden page opens `/<username>/`, and the
    /// header, first grid page and highlights are read from the page's own queries. Calling Instagram's
    /// older REST endpoints directly gets the account rate limited ("feedback_required").
    func loadProfile() async {
        guard profilePhase != .loading else { return }
        profilePhase = .loading
        let token = profileToken

        var username = profileUsername
        if username == nil, (profileUserID ?? viewerID) == viewerID {
            username = await resolveViewerUsername()
        }
        guard token == profileToken else { return }
        guard let username, !username.isEmpty else {
            profilePhase = profile == nil ? .failed("Kullanıcı adın bulunamadı. Yenilemeyi dene.") : .loaded
            return
        }

        let loaded = await openProfilePage(username: username, token: token)
        guard token == profileToken else { return }
        guard let user = loaded?.merged(over: profile) else {
            profilePhase = profile == nil ? .failed("Profil yüklenemedi. İnternet bağlantını kontrol edip yenile.") : .loaded
            return
        }
        profile = user
        if user.id == viewerID { viewerUsername = user.username }
        profilePhase = .loaded
        if profileSection != .posts, canSeeContent(of: user) {
            await loadProfileSection(profileSection)
        }
    }

    /// The signed-in account's username: known already, from the edit-profile endpoint the web app uses,
    /// from the page, or from any loaded tray, note or post of the viewer's.
    private func resolveViewerUsername() async -> String? {
        if let viewerUsername { return viewerUsername }
        if let name = await api.currentUser() {
            viewerUsername = name
            return name
        }
        var name = viewer?.username
        if name == nil { name = await client.detectViewerUsername() }
        if let name { viewerUsername = name }
        return name
    }

    /// Opens `/<username>/` in the hidden page and waits for its profile query (matched by username so a
    /// late response for another profile is ignored). The posts and highlights queries that come with it
    /// fill the grid and the highlights row as they arrive.
    private func openProfilePage(username: String, token: UUID) async -> IGUser? {
        await client.withPage("profile \(username)") {
            // Another flow may have held the page meanwhile; this request may already be stale.
            guard token == profileToken else { return }
            pageProfileTarget = username.lowercased()
            pageProfileUser = nil
            capture = .posts
            _ = await client.navigate(to: "/\(username)/")
            for _ in 0..<60 {
                try? await Task.sleep(for: .milliseconds(250))
                guard token == profileToken else { return }
                if pageProfileUser != nil && profileGrids[.posts]?.phase == .loaded { break }
            }
        }
        guard token == profileToken else { return nil }
        if pageProfileUser != nil, profileGrids[.posts] == nil {
            // The posts query never came (private account, or still on its way): show an empty, finished grid.
            profileGrids[.posts] = PostPage(phase: .loaded)
        }
        return pageProfileUser
    }

    func canSeeContent(of user: IGUser) -> Bool {
        !user.isPrivate || user.isFollowing == true || user.id == viewerID
    }

    func availableSections(for user: IGUser) -> [ProfileSection] {
        user.id == viewerID ? ProfileSection.allCases : [.posts, .reels, .tagged]
    }

    func selectProfileSection(_ section: ProfileSection) {
        guard section != profileSection else { return }
        withAnimation(.snappy(duration: 0.25)) { profileSection = section }
        if profileGrids[section] == nil {
            Task { await loadProfileSection(section) }
        }
    }

    /// Loads a profile grid by opening its tab in the hidden page (`/<username>/reels/` …), or the next page
    /// by scrolling the hidden page, exactly as a visitor of instagram.com would. Posts arrive through
    /// `handleNetworkEvent` while `capture` names the section.
    func loadProfileSection(_ section: ProfileSection, more: Bool = false) async {
        guard let user = profile, canSeeContent(of: user) else { return }
        let token = profileToken
        var page = profileGrids[section] ?? PostPage()
        let before = page.items.count

        if more {
            guard page.cursor != nil, !page.isLoadingMore, page.phase == .loaded, capture == section || section == .posts else { return }
            page.isLoadingMore = true
            profileGrids[section] = page
        } else {
            guard page.phase != .loading else { return }
            profileGrids[section] = PostPage(phase: .loading)
        }

        await client.withPage("profile \(section) \(more ? "more" : "first")") {
            guard token == profileToken else { return }
            capture = section
            if more {
                await client.scrollToBottom()
            } else {
                _ = await client.navigate(to: section.path(for: user.username))
            }
            for _ in 0..<(more ? 24 : 40) {
                try? await Task.sleep(for: .milliseconds(250))
                guard token == profileToken else { return }
                let current = profileGrids[section] ?? PostPage()
                if current.items.count > (more ? before : 0) { break }
                if !more, current.phase == .loaded { break }
            }
        }
        guard token == profileToken else { return }
        var updated = profileGrids[section] ?? PostPage()
        if more && updated.items.count == before { updated.cursor = nil }
        updated.isLoadingMore = false
        updated.phase = .loaded
        profileGrids[section] = updated
    }

    /// Adds posts the hidden page received to the grid that is being captured.
    private func receiveProfilePosts(_ posts: [IGPost], for section: ProfileSection, hasMore: Bool?) {
        var page = profileGrids[section] ?? PostPage()
        let known = Set(page.items.map(\.id))
        let fresh = posts.filter { !known.contains($0.id) }
        page.items += fresh
        page.phase = .loaded
        if let hasMore {
            page.cursor = hasMore ? "page" : nil
        } else if !fresh.isEmpty {
            page.cursor = "page"
        }
        profileGrids[section] = page
    }

    func toggleFollow(_ user: IGUser) {
        let isOn = user.isFollowing == true || user.isRequested
        let target = !isOn
        haptic(.alignment)
        updateProfile(user.id) {
            if target && $0.isPrivate {
                $0.isRequested = true
            } else {
                if $0.isFollowing == true, let count = $0.followerCount { $0.followerCount = max(0, count - 1) }
                if target, let count = $0.followerCount { $0.followerCount = count + 1 }
                $0.isFollowing = target
                $0.isRequested = false
            }
        }
        Task {
            do {
                if let status = try await run({ try await $0.setFollowing(userID: user.id, follow: target) }) {
                    updateProfile(user.id) {
                        $0.isFollowing = status.following?.value ?? $0.isFollowing
                        $0.isRequested = status.outgoing_request?.value ?? $0.isRequested
                    }
                }
            } catch {
                updateProfile(user.id) {
                    $0.isFollowing = user.isFollowing
                    $0.isRequested = user.isRequested
                    $0.followerCount = user.followerCount
                }
            }
        }
    }

    private func updateProfile(_ id: String, _ change: (inout IGUser) -> Void) {
        if var current = profile, current.id == id {
            change(&current)
            profile = current
        }
    }

    /// Followers or following of a user, one page at a time.
    func loadFollowList(userID: String, kind: FollowListKind, cursor: String?) async throws -> ([IGUser], String?) {
        try await run { try await $0.friendshipList(userID: userID, kind: kind, cursor: cursor) }
    }

    /// Opens the chat with a user from their profile, or the inbox filtered to them when there is none yet.
    func openDirect(with user: IGUser) {
        if let existing = directThreads.first(where: { !$0.isGroup && $0.users.first?.id == user.id }) {
            selectThread(existing)
        } else {
            pendingDirectSearch = user.username
        }
        select(.direct)
    }

    func loadComments(for postID: String) async throws -> [IGComment] {
        try await run { try await $0.comments(postID: postID) }
    }

    // MARK: Actions

    func livePost(_ id: String) -> IGPost? {
        feed.first(where: { $0.id == id })
            ?? explore.first(where: { $0.id == id })
            ?? reels.first(where: { $0.id == id })
            ?? profileGrids.values.lazy.compactMap { $0.items.first(where: { $0.id == id }) }.first
    }

    private func mutate(_ id: String, _ change: (inout IGPost) -> Void) {
        if let index = feed.firstIndex(where: { $0.id == id }) { change(&feed[index]) }
        if let index = explore.firstIndex(where: { $0.id == id }) { change(&explore[index]) }
        if let index = reels.firstIndex(where: { $0.id == id }) { change(&reels[index]) }
        for section in profileGrids.keys {
            if let index = profileGrids[section]?.items.firstIndex(where: { $0.id == id }) {
                change(&profileGrids[section]!.items[index])
            }
        }
        if var open = detailPost, open.id == id {
            change(&open)
            detailPost = open
        }
    }

    func toggleLike(_ post: IGPost) {
        let target = !(livePost(post.id)?.hasLiked ?? post.hasLiked)
        haptic(.levelChange)
        mutate(post.id) { $0.hasLiked = target; $0.likeCount += target ? 1 : -1 }
        Task {
            do {
                try await run { try await $0.setLiked(postID: post.id, liked: target) }
            } catch {
                mutate(post.id) { $0.hasLiked = !target; $0.likeCount += target ? -1 : 1 }
            }
        }
    }

    func toggleSave(_ post: IGPost) {
        let target = !(livePost(post.id)?.hasSaved ?? post.hasSaved)
        haptic(.alignment)
        mutate(post.id) { $0.hasSaved = target }
        Task {
            do {
                try await run { try await $0.setSaved(postID: post.id, saved: target) }
            } catch {
                mutate(post.id) { $0.hasSaved = !target }
            }
        }
    }

    func addComment(to postID: String, text: String) async throws -> IGComment? {
        let comment = try await run { try await $0.addComment(postID: postID, text: text) }
        mutate(postID) { $0.commentCount += 1 }
        return comment
    }

    func share(_ post: IGPost, to thread: IGDirectThread, note: String = "") {
        let kindPath = (post.isVideo && reels.contains(where: { $0.id == post.id })) ? "reel" : "p"
        let permalink = "https://www.instagram.com/\(kindPath)/\(post.code)/"
        haptic(.levelChange)
        sendDirectMessage(text: permalink, in: thread)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNote.isEmpty {
            sendDirectMessage(text: trimmedNote, in: thread)
        }
    }

    func markStorySeen(_ id: String) {
        if let index = stories.firstIndex(where: { $0.id == id }), stories[index].hasUnseen {
            stories[index].hasUnseen = false
            stories[index].seenAt = Date.now.timeIntervalSince1970
        }
    }
}
