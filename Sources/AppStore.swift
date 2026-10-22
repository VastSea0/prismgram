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
    var storyViewer: IGStoryTray?
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

    private(set) var profile: IGUser?
    private(set) var profilePosts: [IGPost] = []
    private(set) var profilePhase: Phase = .idle

    // MARK: Session

    func bootstrap() async {
        guard let id = await client.viewerID() else {
            session = .signedOut
            return
        }
        viewerID = id
        await client.prepare()
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
        profile = nil; profilePosts = []; profilePhase = .idle
    }

    // MARK: Navigation

    func select(_ newTab: InstagramTab) {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        withAnimation(.snappy(duration: 0.25)) {
            if newTab == .profile && tab != .profile { profileUserID = nil; profilePhase = .idle }
            tab = newTab
        }
    }

    func openProfile(of user: IGUser) {
        detailPost = nil
        storyViewer = nil
        profileUserID = user.id == viewerID ? nil : user.id
        profilePhase = .idle
        profile = nil
        profilePosts = []
        withAnimation(.snappy(duration: 0.25)) { tab = .profile }
    }

    func closeOtherProfile() {
        profileUserID = nil
        profilePhase = .idle
        profile = nil
        profilePosts = []
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
        case .profile:
            if profilePhase == .idle { await loadProfile() }
        case .direct:
            break
        }
    }

    func refresh(_ tab: InstagramTab) async {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        switch tab {
        case .home: feedCursor = nil; await loadHome()
        case .explore: await loadExplore()
        case .reels: await loadReels()
        case .activity: await loadActivity()
        case .profile: await loadProfile()
        case .direct: break
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
            }
            let json = try await fetch("/api/v1/feed/timeline/", method: "POST", body: "reason=cold_start_fetch&is_pull_to_refresh=0")
            feed = Self.feedPosts(from: json)
            feedCursor = IGJSON.string(json["next_max_id"])
            feedPhase = .loaded
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

    func loadProfile() async {
        guard profilePhase != .loading, let id = profileUserID ?? viewerID else { return }
        profilePhase = .loading
        do {
            let info = try await fetch("/api/v1/users/\(id)/info/")
            if let userDict = info["user"] as? [String: Any] {
                profile = IGJSON.user(userDict)
            }
            let feedJSON = try await fetch("/api/v1/feed/user/\(id)/?count=18")
            profilePosts = ((feedJSON["items"] as? [[String: Any]]) ?? []).compactMap(IGJSON.post)
            profilePhase = .loaded
        } catch {
            profilePhase = .failed(message(for: error))
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

    func openMessagesInBrowser() {
        if let url = URL(string: "https://www.instagram.com/direct/inbox/") { NSWorkspace.shared.open(url) }
    }
}
