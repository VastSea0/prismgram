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
    var isLoadingStorySlides = false
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

    private(set) var profile: IGUser?
    private(set) var profilePosts: [IGPost] = []
    private(set) var profileHighlights: [IGStoryTray] = []
    private(set) var profilePhase: Phase = .idle

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
        profile = nil; profilePosts = []; profileHighlights = []; profilePhase = .idle
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

        case "PolarisProfilePageContentQuery":
            if let dataDict = json["data"] as? [String: Any],
               let userDict = dataDict["user"] as? [String: Any],
               let parsedUser = IGJSON.user(userDict) {
                let targetUsername = (profileUsername ?? viewerUsername)?.lowercased()
                let targetID = profileUserID ?? viewerID
                if parsedUser.id == targetID || parsedUser.username.lowercased() == targetUsername || profile == nil {
                    profile = parsedUser
                    if parsedUser.id == viewerID {
                        viewerUsername = parsedUser.username
                    }
                    profilePhase = .loaded
                }
            }

        case "PolarisProfilePostsQuery":
            if let dataDict = json["data"] as? [String: Any],
               let conn = dataDict["xdt_api__v1__feed__user_timeline_graphql_connection"] as? [String: Any],
               let edges = conn["edges"] as? [[String: Any]] {
                let posts = edges.compactMap { ($0["node"] as? [String: Any]).flatMap(IGJSON.post) }
                if !posts.isEmpty {
                    let owner = posts.first?.user
                    let targetUsername = (profileUsername ?? viewerUsername)?.lowercased()
                    let targetID = profileUserID ?? viewerID
                    if owner?.id == targetID || owner?.username.lowercased() == targetUsername || profilePosts.isEmpty {
                        profilePosts = posts
                        if profile == nil, let owner {
                            profile = owner
                        }
                        profilePhase = .loaded
                    }
                }
            }

        case "PolarisProfileStoryHighlightsTrayContentQuery":
            let parsed = IGJSON.highlights(from: json, fallbackUser: profile)
            if !parsed.isEmpty {
                profileHighlights = parsed
            }

        default:
            if event.url.contains("reels_media") {
                if let current = storyViewer {
                    let slides = IGJSON.storySlides(from: json, reelID: current.id)
                    if !slides.isEmpty {
                        applyStorySlides(slides, for: current.id)
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
                updated.messages = detailed.messages
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
            if newTab == .profile && tab != .profile {
                profileUserID = nil
                profileUsername = nil
                profilePhase = .idle
            }
            tab = newTab
        }
    }

    func openProfile(of user: IGUser) {
        detailPost = nil
        storyViewer = nil
        let isOwn = user.id == viewerID
        profileUserID = isOwn ? nil : user.id
        profileUsername = isOwn ? viewerUsername ?? user.username : user.username
        profilePhase = .idle
        profile = user
        profilePosts = []
        profileHighlights = []
        withAnimation(.snappy(duration: 0.25)) { tab = .profile }
        Task { await loadProfile() }
    }

    func closeOtherProfile() {
        profileUserID = nil
        profileUsername = nil
        profilePhase = .idle
        profile = nil
        profilePosts = []
        profileHighlights = []
    }

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

    func openStory(_ tray: IGStoryTray) {
        markStorySeen(tray.id)
        storyViewer = tray
        if tray.slides.isEmpty {
            Task { await loadStorySlides(for: tray) }
        }
    }

    func loadStorySlides(for tray: IGStoryTray) async {
        isLoadingStorySlides = true
        defer { isLoadingStorySlides = false }

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
            // Fallback to driving the hidden WebView to the story route so its own fetch triggers
        }

        _ = await client.navigate(to: "/stories/\(tray.user.username)/")
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(350))
            if let current = storyViewer, current.id == tray.id, !current.slides.isEmpty {
                break
            }
        }
    }

    private func applyStorySlides(_ slides: [IGMediaItem], for trayID: String) {
        if let index = stories.firstIndex(where: { $0.id == trayID }) {
            stories[index].slides = slides
        }
        if let index = profileHighlights.firstIndex(where: { $0.id == trayID }) {
            profileHighlights[index].slides = slides
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

    func sendDirectMessage(text: String, in thread: IGDirectThread) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSendingDirectMessage else { return false }
        isSendingDirectMessage = true
        defer { isSendingDirectMessage = false }

        await client.openDirectThread(
            threadID: thread.id,
            title: thread.title,
            username: thread.users.first?.username
        )
        try? await Task.sleep(for: .milliseconds(350))

        let sent = await client.sendDirectMessage(text: trimmed)
        if sent, let idx = directThreads.firstIndex(where: { $0.id == thread.id }) {
            let optimistic = IGDirectMessage(
                id: UUID().uuidString,
                senderFBID: thread.viewerFBID,
                senderUsername: viewerUsername,
                senderAvatarURL: nil,
                text: trimmed,
                timestamp: .now,
                isFromViewer: true
            )
            directThreads[idx].messages.append(optimistic)
            directThreads[idx].snippet = trimmed
            directThreads[idx].lastActivityAt = .now
        }
        return sent
    }

    // MARK: Profile

    func loadProfile() async {
        guard profilePhase != .loading else { return }
        profilePhase = .loading

        let targetID = profileUserID ?? viewerID
        var targetUsername = profileUsername ?? (targetID == viewerID ? viewerUsername : nil)

        if targetUsername == nil, let id = targetID {
            targetUsername = stories.first(where: { $0.user.id == id })?.user.username
                ?? feed.first(where: { $0.user.id == id })?.user.username
                ?? notes.first(where: { $0.user.id == id })?.user.username
        }
        if targetUsername == nil && targetID == viewerID {
            targetUsername = await client.detectViewerUsername()
            if let targetUsername { viewerUsername = targetUsername }
        }

        if let username = targetUsername, !username.isEmpty {
            _ = await client.navigate(to: "/\(username)/")
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(400))
                if profile?.followerCount != nil && !profilePosts.isEmpty {
                    profilePhase = .loaded
                    return
                }
            }
        }

        // Fallback to user feed endpoint if GraphQL tap hasn't populated posts yet
        if let id = targetID {
            if let feedJSON = try? await fetch("/api/v1/feed/user/\(id)/?count=18") {
                let items = ((feedJSON["items"] as? [[String: Any]]) ?? []).compactMap(IGJSON.post)
                if !items.isEmpty {
                    profilePosts = items
                    if profile == nil {
                        profile = items.first?.user
                    }
                }
                if let userDict = feedJSON["user"] as? [String: Any], let parsed = IGJSON.user(userDict), profile == nil {
                    profile = parsed
                }
            }
        }

        if profile != nil || !profilePosts.isEmpty {
            profilePhase = .loaded
        } else {
            profilePhase = .failed("Profil bilgileri alınamadı. Birkaç saniye sonra yenileyin.")
        }
    }

    func toggleFollow(_ user: IGUser) {
        guard let current = user.isFollowing else { return }
        let target = !current
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        if profile?.id == user.id {
            profile?.isFollowing = target
            if let count = profile?.followerCount {
                profile?.followerCount = max(0, count + (target ? 1 : -1))
            }
        }
        Task {
            do {
                _ = try await fetch(
                    "/api/v1/friendships/\(target ? "create" : "destroy")/\(user.id)/",
                    method: "POST",
                    body: "user_id=\(encode(user.id))"
                )
            } catch {
                if profile?.id == user.id {
                    profile?.isFollowing = current
                }
            }
        }
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
            ?? profilePosts.first(where: { $0.id == id })
    }

    private func mutate(_ id: String, _ change: (inout IGPost) -> Void) {
        if let index = feed.firstIndex(where: { $0.id == id }) { change(&feed[index]) }
        if let index = explore.firstIndex(where: { $0.id == id }) { change(&explore[index]) }
        if let index = reels.firstIndex(where: { $0.id == id }) { change(&reels[index]) }
        if let index = profilePosts.firstIndex(where: { $0.id == id }) { change(&profilePosts[index]) }
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
        if let index = stories.firstIndex(where: { $0.id == id }) { stories[index].hasUnseen = false }
    }
}
