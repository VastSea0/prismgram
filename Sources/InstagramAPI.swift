import Foundation

/// Typed wrappers around every Instagram `/api/v1/` endpoint used by the app.
///
/// Centralizing paths and request bodies here keeps `AppStore` free of raw endpoint strings and
/// gives a single place to update when an endpoint path or parameter changes.
@MainActor
struct InstagramAPI {
    let transport: any InstagramTransport

    // MARK: Feed & Stories

    func reelsTray() async throws -> [String: Any] {
        try await fetch("/api/v1/feed/reels_tray/")
    }

    func timeline(cursor: String? = nil) async throws -> APITimelineResponse {
        let body: String
        if let cursor {
            body = "reason=pagination&is_pull_to_refresh=0&max_id=\(Self.encode(cursor))"
        } else {
            body = "reason=cold_start_fetch&is_pull_to_refresh=0"
        }
        return try await fetchDecoded(APITimelineResponse.self, "/api/v1/feed/timeline/", method: "POST", body: body)
    }

    func reelsMedia(reelID: String) async throws -> [String: Any] {
        try await fetch(
            "/api/v1/feed/reels_media/",
            method: "POST",
            body: "reel_ids=\(Self.encode(reelID))"
        )
    }

    // MARK: Explore, Reels, Search & Activity

    func exploreGrid() async throws -> [IGPost] {
        let decoded = try await fetchDecoded(APIExploreResponse.self, "/api/v1/discover/web/explore_grid/")
        return decoded.posts
    }

    func clipsDiscover(cursor: String? = nil) async throws -> [String: Any] {
        var body = "page_size=8&include_feed_video=true"
        if let cursor {
            body += "&max_id=\(Self.encode(cursor))"
        }
        return try await fetch("/api/v1/clips/discover/", method: "POST", body: body)
    }

    func topSearch(query: String) async throws -> [String: Any] {
        try await fetch("/api/v1/web/search/topsearch/?context=blended&query=\(Self.encode(query))&include_reel=true")
    }

    func newsInbox() async throws -> [String: Any] {
        try await fetch("/api/v1/news/inbox/")
    }

    // MARK: Direct & Notes

    /// Calls `direct_v2/threads/broadcast/<kind>/` directly on the transport so an unsupported
    /// endpoint never signs the user out; returns the payload when Instagram answers `ok`.
    func broadcast(kind: String, fields: [String: String]) async -> [String: Any]? {
        let token = String((0..<19).map { _ in "0123456789".randomElement()! })
        var parameters = fields
        parameters["action"] = parameters["action"] ?? "send_item"
        parameters["client_context"] = token
        parameters["mutation_token"] = token
        parameters["offline_threading_id"] = token
        let body = parameters.map { "\($0.key)=\(Self.encode($0.value))" }.joined(separator: "&")
        guard let response = try? await transport.request(
            "/api/v1/direct_v2/threads/broadcast/\(kind)/",
            method: "POST",
            body: body
        ),
        (200..<300).contains(response.status),
        let json = response.json,
        (json["status"] as? String) == "ok" else { return nil }
        return json
    }

    func createNote(text: String, closeFriends: Bool) async -> [String: Any]? {
        guard let response = try? await transport.request(
            "/api/v1/notes/create_note/",
            method: "POST",
            body: "note_style=0&text=\(Self.encode(text))&audience=\(closeFriends ? 1 : 0)"
        ),
        (200..<300).contains(response.status),
        (response.json?["status"] as? String) == "ok" else { return nil }
        return response.json
    }

    func deleteNote(id: String) async -> Bool {
        guard let response = try? await transport.request(
            "/api/v1/notes/delete_note/",
            method: "POST",
            body: "id=\(Self.encode(id))"
        ),
        (200..<300).contains(response.status) else { return false }
        return true
    }

    // MARK: Account & Profile

    func logout() async {
        _ = try? await transport.request(
            "/api/v1/web/accounts/logout/ajax/",
            method: "POST",
            body: "one_tap_app_login=0"
        )
    }

    func setPrivacy(isPrivate: Bool) async -> Bool {
        guard let response = try? await transport.request(
            "/api/v1/accounts/\(isPrivate ? "set_private" : "set_public")/",
            method: "POST",
            body: ""
        ),
        (200..<300).contains(response.status) else { return false }
        return true
    }

    func currentUser() async -> [String: Any]? {
        guard let response = try? await transport.request("/api/v1/accounts/current_user/?edit=true"),
              (200..<300).contains(response.status) else { return nil }
        return response.json
    }

    func setFollowing(userID: String, follow: Bool) async throws -> [String: Any] {
        try await fetch(
            "/api/v1/friendships/\(follow ? "create" : "destroy")/\(userID)/",
            method: "POST",
            body: "container_module=profile&user_id=\(Self.encode(userID))"
        )
    }

    func friendshipList(userID: String, kind: FollowListKind, cursor: String?) async throws -> [String: Any] {
        var path = "/api/v1/friendships/\(userID)/\(kind.rawValue)/?count=24"
        if kind == .followers { path += "&search_surface=follow_list_page" }
        if let cursor { path += "&max_id=\(Self.encode(cursor))" }
        return try await fetch(path)
    }

    // MARK: Media interactions

    func comments(postID: String) async throws -> [IGComment] {
        let decoded = try await fetchDecoded(
            APICommentsResponse.self,
            "/api/v1/media/\(postID)/comments/?can_support_threading=true&permalink_enabled=false"
        )
        return decoded.items
    }

    func setLiked(postID: String, liked: Bool) async throws {
        _ = try await fetch("/api/v1/web/likes/\(postID)/\(liked ? "like" : "unlike")/", method: "POST", body: "")
    }

    func setSaved(postID: String, saved: Bool) async throws {
        _ = try await fetch("/api/v1/web/save/\(postID)/\(saved ? "save" : "unsave")/", method: "POST", body: "")
    }

    func addComment(postID: String, text: String) async throws -> IGComment? {
        let decoded = try await fetchDecoded(
            APIAddCommentResponse.self,
            "/api/v1/web/comments/\(postID)/add/",
            method: "POST",
            body: "comment_text=\(Self.encode(text))"
        )
        return decoded.createdComment
    }

    // MARK: Envelope handling

    enum Failure: Error {
        case unauthorized
        case rejected(String)
    }

    private func fetchDecoded<T: Decodable>(_ type: T.Type, _ path: String, method: String = "GET", body: String? = nil) async throws -> T {
        let response = try await rawFetch(path, method: method, body: body)
        let data: Data
        if let rawData = response.data {
            data = rawData
        } else if let json = response.json, let serialized = try? JSONSerialization.data(withJSONObject: json) {
            data = serialized
        } else {
            throw Failure.rejected("Instagram isteği reddetti (HTTP \(response.status)).")
        }
        do {
            return try APIDecoding.decode(T.self, from: data, endpoint: path)
        } catch {
            throw Failure.rejected("Instagram yanıtı okunamadı.")
        }
    }

    private func fetch(_ path: String, method: String = "GET", body: String? = nil) async throws -> [String: Any] {
        let response = try await rawFetch(path, method: method, body: body)
        guard let json = response.json else {
            throw Failure.rejected("Instagram isteği reddetti (HTTP \(response.status)).")
        }
        return json
    }

    private func rawFetch(_ path: String, method: String = "GET", body: String? = nil) async throws -> InstagramClient.Response {
        let response: InstagramClient.Response
        do {
            response = try await transport.request(path, method: method, body: body)
        } catch {
            throw Failure.rejected("Instagram'a bağlanılamadı.")
        }

        if response.status == 401 || (response.json?["message"] as? String) == "login_required" {
            throw Failure.unauthorized
        }
        if response.status == 429 {
            throw Failure.rejected("Instagram istekleri geçici olarak sınırladı. Birkaç dakika sonra yenileyin.")
        }
        guard (200..<300).contains(response.status), response.json != nil else {
            let detail = (response.json?["message"] as? String) ?? (response.json == nil ? "non-JSON body" : "-")
            InstagramClient.debugLog("rejected \(path): \(detail)")
            let reason = (response.json?["feedback_message"] as? String)
                ?? (response.json?["message"] as? String)
                ?? "Instagram isteği reddetti (HTTP \(response.status))."
            throw Failure.rejected(reason)
        }
        return response
    }

    static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? text
    }
}
