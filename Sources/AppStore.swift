import SwiftUI
import AppKit
import Observation

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

    /// One paginated grid of posts.
    struct PostPage {
        var items: [IGPost] = []
        var phase: Phase = .idle
        var cursor: String?
        var isLoadingMore = false
    }

    let client = InstagramClient()

    // Session
    private(set) var session: Session = .unknown
    private(set) var viewerID: String?
    private(set) var viewerUsername: String?

    // Navigation / presentation
    var layoutMode: AppLayoutMode = .hybrid {
        didSet {
            guard oldValue != layoutMode else { return }
            isInspectorShown = layoutMode == .desktop
        }
    }
    private(set) var tab: InstagramTab = .home
    var isInspectorShown = false
    var profileUserID: String?
    var profileUsername: String?
    var storyViewer: IGStoryTray?
    /// The trays the open story viewer moves through (the home tray or a profile's highlights).
    private(set) var storyQueue: [IGStoryTray] = []
    private var loadingStoryIDs: Set<String> = []
    var detailPost: IGPost?
    var isShowingLogin = false

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

    private(set) var activity: [IGActivity] = []
    private(set) var activityPhase: Phase = .idle

    private(set) var notes: [IGNote] = []
    private(set) var directThreads: [IGDirectThread] = []
    private(set) var directPhase: Phase = .idle
    var selectedThreadID: String?
    private(set) var isSendingDirectMessage = false
    private var sendChain: Task<Void, Never>?

    private(set) var profile: IGUser?
    private(set) var profileGrids: [ProfileSection: PostPage] = [:]
    var profileSection: ProfileSection = .posts
    private(set) var profileHighlights: [IGStoryTray] = []
    private(set) var profilePhase: Phase = .idle
    /// Other people's profiles opened on top of each other, newest last; Back walks down this stack.
    private(set) var profileStack: [IGUser] = []
    private var profileReturnTab: InstagramTab?
    private var profileToken = UUID()
    /// Set when "Message" is pressed on a profile with no existing chat, so the inbox opens filtered to that person.
    var pendingDirectSearch: String?

    var profilePosts: [IGPost] { profileGrids[.posts]?.items ?? [] }
    var isViewingOtherProfile: Bool { profileUserID != nil }

    init() {
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

        switch opName {
        case "IGDInboxTrayQuery", "PolarisProfileNoteBubbleQuery":
            let parsed = IGJSON.notes(from: json)
            if !parsed.isEmpty {
                notes = parsed
                if let own = parsed.first(where: { $0.user.id == viewerID }) {
                    viewerUsername = own.user.username
                }
            }

        case "PolarisDirectInboxQuery":
            let parsed = IGJSON.directThreads(from: json)
            if !parsed.isEmpty {
                mergeThreads(parsed)
                if selectedThreadID == nil {
                    selectedThreadID = directThreads.first?.id
                }
                directPhase = .loaded
            } else if directPhase == .loading {
                directPhase = .loaded
            }

        case "IGDThreadDetailQuery":
            if let detailed = IGJSON.directThreadDetail(from: json) {
                mergeDetailedThread(detailed)
            }

        default:
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
                let confirmed = Set(detailed.messages.filter(\.isFromViewer).map(\.text))
                updated.messages = detailed.messages + local.filter { $0.delivery == .failed || !confirmed.contains($0.text) }
            }
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
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
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
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
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

    private func fetch(_ path: String, method: String = "GET", body: String? = nil) async throws -> [String: Any] {
        let response: InstagramClient.Response
        do {
            response = try await client.request(path, method: method, body: body)
        } catch {
            throw RequestFailure(message: "Instagram'a bağlanılamadı.")
        }

        if response.status == 401 || (response.json?["message"] as? String) == "login_required" {
            session = .signedOut
            throw RequestFailure(message: "Oturum süresi doldu. Yeniden giriş yapın.")
        }
        if response.status == 429 {
            throw RequestFailure(message: "Instagram istekleri geçici olarak sınırladı. Birkaç dakika sonra yenileyin.")
        }
        guard (200..<300).contains(response.status), let json = response.json else {
            let reason = (response.json?["feedback_message"] as? String)
                ?? (response.json?["message"] as? String)
                ?? "Instagram isteği reddetti (HTTP \(response.status))."
            throw RequestFailure(message: reason)
        }
        return json
    }

    private func message(for error: Error) -> String {
        (error as? RequestFailure)?.message ?? "Beklenmeyen bir hata oluştu."
    }

    private func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? text
    }

    // MARK: Loaders

    func loadHome() async {
        guard feedPhase != .loading else { return }
        feedPhase = .loading
        do {
            if let trayJSON = try? await fetch("/api/v1/feed/reels_tray/") {
                let tray = (trayJSON["tray"] as? [[String: Any]]) ?? []
                stories = tray.compactMap(IGJSON.storyTray)
                if let ownTray = stories.first(where: { $0.user.id == viewerID }) {
                    viewerUsername = ownTray.user.username
                }
            }
            let json = try await fetch("/api/v1/feed/timeline/", method: "POST", body: "reason=cold_start_fetch&is_pull_to_refresh=0")
            feed = Self.feedPosts(from: json)
            feedCursor = IGJSON.string(json["next_max_id"])
            feedPhase = .loaded
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
            let json = try await fetch(
                "/api/v1/feed/timeline/",
                method: "POST",
                body: "reason=pagination&is_pull_to_refresh=0&max_id=\(encode(cursor))"
            )
            let known = Set(feed.map(\.id))
            feed += Self.feedPosts(from: json).filter { !known.contains($0.id) }
            feedCursor = IGJSON.string(json["next_max_id"])
        } catch {
            feedCursor = nil
        }
    }

    private static func feedPosts(from json: [String: Any]) -> [IGPost] {
        let wrappers = (json["feed_items"] as? [[String: Any]]) ?? []
        return wrappers.compactMap { wrapper in
            guard let media = wrapper["media_or_ad"] as? [String: Any],
                  media["ad_id"] == nil, media["injected"] == nil else { return nil }
            return IGJSON.post(media)
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
        if latest(tray).slides.isEmpty {
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
            let json = try await fetch(
                "/api/v1/feed/reels_media/",
                method: "POST",
                body: "reel_ids=\(encode(tray.id))"
            )
            let slides = IGJSON.storySlides(from: json, reelID: tray.id)
            if !slides.isEmpty {
                applyStorySlides(slides, for: tray.id)
                return
            }
        } catch {
            // Fall back to driving the hidden page to the story route so its own fetch is tapped.
        }

        guard !tray.id.hasPrefix("highlight:") else { return }
        _ = await client.navigate(to: "/stories/\(tray.user.username)/")
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(350))
            if !latest(tray).slides.isEmpty { break }
        }
    }

    private func applyStorySlides(_ slides: [IGMediaItem], for trayID: String) {
        if let index = stories.firstIndex(where: { $0.id == trayID }) {
            stories[index].slides = slides
        }
        if let index = profileHighlights.firstIndex(where: { $0.id == trayID }) {
            profileHighlights[index].slides = slides
        }
        if let index = storyQueue.firstIndex(where: { $0.id == trayID }) {
            storyQueue[index].slides = slides
        }
        if var current = storyViewer, current.id == trayID {
            current.slides = slides
            storyViewer = current
        }
    }

    func loadExplore() async {
        guard explorePhase != .loading else { return }
        explorePhase = .loading
        do {
            let json = try await fetch("/api/v1/discover/web/explore_grid/")
            explore = IGJSON.collectPosts(in: json)
            explorePhase = .loaded
        } catch {
            explorePhase = .failed(message(for: error))
        }
    }

    func loadReels() async {
        guard reelsPhase != .loading else { return }
        reelsPhase = .loading
        do {
            let json = try await fetch("/api/v1/clips/discover/", method: "POST", body: "page_size=8&include_feed_video=true")
            reels = IGJSON.collectPosts(in: json).filter(\.isVideo)
            reelsPhase = .loaded
        } catch {
            reelsPhase = .failed(message(for: error))
        }
    }

    func loadActivity() async {
        guard activityPhase != .loading else { return }
        activityPhase = .loading
        do {
            let json = try await fetch("/api/v1/news/inbox/")
            activity = IGJSON.activities(in: json)
            activityPhase = .loaded
        } catch {
            activityPhase = .failed(message(for: error))
        }
    }

    // MARK: Direct Messages & Notes

    func loadDirect() async {
        guard directPhase != .loading else { return }
        directPhase = .loading
        _ = await client.navigate(to: "/direct/inbox/")

        for _ in 0..<24 {
            try? await Task.sleep(for: .milliseconds(400))
            if !directThreads.isEmpty {
                directPhase = .loaded
                return
            }
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
            await client.openDirectThread(
                threadID: thread.id,
                title: thread.title,
                username: thread.users.first?.username
            )
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
            await client.openDirectThread(threadID: thread.id, title: thread.title, username: thread.users.first?.username)
            try? await Task.sleep(for: .milliseconds(350))
            let sent = await client.sendDirectMessage(text: message.text)
            setDelivery(sent ? .sent : .failed, for: message.id, in: threadID)
        }
    }

    private func setDelivery(_ delivery: IGDirectMessage.Delivery, for messageID: String, in threadID: String) {
        guard let threadIndex = directThreads.firstIndex(where: { $0.id == threadID }),
              let messageIndex = directThreads[threadIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }
        directThreads[threadIndex].messages[messageIndex].delivery = delivery
    }

    func markThreadRead(_ thread: IGDirectThread, _ isRead: Bool = true) {
        if let index = directThreads.firstIndex(where: { $0.id == thread.id }) {
            directThreads[index].isUnread = !isRead
        }
    }

    // MARK: Profile

    func loadProfile() async {
        guard profilePhase != .loading else { return }
        profilePhase = .loading
        let token = profileToken

        let targetID = profileUserID ?? viewerID
        var username = profileUsername ?? (targetID == viewerID ? viewerUsername : nil)
        if username == nil, targetID == viewerID, let detected = await client.detectViewerUsername() {
            viewerUsername = detected
            username = detected
        }

        var loaded: IGUser?
        var failure: Error?
        do {
            if let username, !username.isEmpty {
                let json = try await fetch("/api/v1/users/web_profile_info/?username=\(encode(username))")
                loaded = ((json["data"] as? [String: Any])?["user"] as? [String: Any]).flatMap(IGJSON.graphUser)
            }
            if loaded == nil, let id = targetID {
                let json = try await fetch("/api/v1/users/\(id)/info/")
                loaded = (json["user"] as? [String: Any]).flatMap(IGJSON.user)
            }
        } catch {
            failure = error
        }
        guard token == profileToken else { return }

        guard let user = loaded?.merged(over: profile) else {
            profilePhase = profile == nil ? .failed(failure.map(message(for:)) ?? "Profil bulunamadı.") : .loaded
            return
        }
        profile = user
        if user.id == viewerID { viewerUsername = user.username }
        profilePhase = .loaded

        Task { await loadHighlights(for: user.id, token: token) }
        if canSeeContent(of: user) {
            await loadProfileSection(profileSection)
        }
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

    /// Loads the first page of a profile grid, or the next page when `more` is set.
    func loadProfileSection(_ section: ProfileSection, more: Bool = false) async {
        guard let user = profile, canSeeContent(of: user) else { return }
        var page = profileGrids[section] ?? PostPage()
        if more {
            guard page.cursor != nil, !page.isLoadingMore, page.phase == .loaded else { return }
            page.isLoadingMore = true
            profileGrids[section] = page
        } else {
            guard page.phase != .loading else { return }
            page = PostPage(phase: .loading)
            profileGrids[section] = page
        }
        let token = profileToken
        let cursor = more ? page.cursor : nil

        do {
            let (posts, next) = try await fetchSection(section, userID: user.id, cursor: cursor)
            guard token == profileToken else { return }
            var updated = profileGrids[section] ?? PostPage()
            let known = Set(updated.items.map(\.id))
            updated.items = more ? updated.items + posts.filter { !known.contains($0.id) } : posts
            updated.cursor = next
            updated.phase = .loaded
            updated.isLoadingMore = false
            profileGrids[section] = updated
        } catch {
            guard token == profileToken else { return }
            var updated = profileGrids[section] ?? PostPage()
            updated.isLoadingMore = false
            if more {
                updated.cursor = nil
            } else {
                updated.phase = .failed(message(for: error))
            }
            profileGrids[section] = updated
        }
    }

    private func fetchSection(_ section: ProfileSection, userID: String, cursor: String?) async throws -> ([IGPost], String?) {
        let maxID = cursor.map { "&max_id=\(encode($0))" } ?? ""
        switch section {
        case .posts:
            let json = try await fetch("/api/v1/feed/user/\(userID)/?count=12\(maxID)")
            let posts = ((json["items"] as? [[String: Any]]) ?? []).compactMap(IGJSON.post)
            return (posts, Self.nextCursor(json))
        case .reels:
            let json = try await fetch(
                "/api/v1/clips/user/",
                method: "POST",
                body: "target_user_id=\(encode(userID))&page_size=12&include_feed_video=true\(maxID)"
            )
            let paging = json["paging_info"] as? [String: Any]
            let more = IGJSON.bool(paging?["more_available"]) ?? false
            return (IGJSON.collectPosts(in: json["items"] ?? []), more ? IGJSON.string(paging?["max_id"]) : nil)
        case .tagged:
            let json = try await fetch("/api/v1/usertags/\(userID)/feed/?count=12\(maxID)")
            return (IGJSON.collectPosts(in: json["items"] ?? []), Self.nextCursor(json))
        case .saved:
            let json = try await fetch("/api/v1/feed/saved/posts/?\(maxID.dropFirst())")
            return (IGJSON.collectPosts(in: json["items"] ?? []), Self.nextCursor(json))
        }
    }

    private static func nextCursor(_ json: [String: Any]) -> String? {
        guard IGJSON.bool(json["more_available"]) ?? (json["next_max_id"] != nil) else { return nil }
        return IGJSON.string(json["next_max_id"])
    }

    private func loadHighlights(for userID: String, token: UUID) async {
        guard let json = try? await fetch("/api/v1/highlights/\(userID)/highlights_tray/"),
              token == profileToken else { return }
        let tray = ((json["tray"] as? [[String: Any]]) ?? []).compactMap(IGJSON.storyTray)
        profileHighlights = tray.map { highlight in
            var item = highlight
            if item.title == nil { item.title = "Öne Çıkan" }
            return item
        }
    }

    func toggleFollow(_ user: IGUser) {
        let isOn = user.isFollowing == true || user.isRequested
        let target = !isOn
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
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
                let json = try await fetch(
                    "/api/v1/friendships/\(target ? "create" : "destroy")/\(user.id)/",
                    method: "POST",
                    body: "container_module=profile&user_id=\(encode(user.id))"
                )
                if let status = json["friendship_status"] as? [String: Any] {
                    updateProfile(user.id) {
                        $0.isFollowing = IGJSON.bool(status["following"]) ?? $0.isFollowing
                        $0.isRequested = IGJSON.bool(status["outgoing_request"]) ?? $0.isRequested
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
        var path = "/api/v1/friendships/\(userID)/\(kind.rawValue)/?count=24"
        if kind == .followers { path += "&search_surface=follow_list_page" }
        if let cursor { path += "&max_id=\(encode(cursor))" }
        let json = try await fetch(path)
        let users = ((json["users"] as? [[String: Any]]) ?? []).compactMap(IGJSON.user)
        return (users, IGJSON.string(json["next_max_id"]))
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
        let json = try await fetch("/api/v1/media/\(postID)/comments/?can_support_threading=true&permalink_enabled=false")
        return ((json["comments"] as? [[String: Any]]) ?? []).compactMap(IGJSON.comment)
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
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
        mutate(post.id) { $0.hasLiked = target; $0.likeCount += target ? 1 : -1 }
        Task {
            do {
                _ = try await fetch("/api/v1/web/likes/\(post.id)/\(target ? "like" : "unlike")/", method: "POST", body: "")
            } catch {
                mutate(post.id) { $0.hasLiked = !target; $0.likeCount += target ? -1 : 1 }
            }
        }
    }

    func toggleSave(_ post: IGPost) {
        let target = !(livePost(post.id)?.hasSaved ?? post.hasSaved)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        mutate(post.id) { $0.hasSaved = target }
        Task {
            do {
                _ = try await fetch("/api/v1/web/save/\(post.id)/\(target ? "save" : "unsave")/", method: "POST", body: "")
            } catch {
                mutate(post.id) { $0.hasSaved = !target }
            }
        }
    }

    func addComment(to postID: String, text: String) async throws -> IGComment? {
        let json = try await fetch(
            "/api/v1/web/comments/\(postID)/add/",
            method: "POST",
            body: "comment_text=\(encode(text))"
        )
        mutate(postID) { $0.commentCount += 1 }
        return IGJSON.comment(json)
    }

    func markStorySeen(_ id: String) {
        if let index = stories.firstIndex(where: { $0.id == id }), stories[index].hasUnseen {
            stories[index].hasUnseen = false
            stories[index].seenAt = Date.now.timeIntervalSince1970
        }
    }
}
