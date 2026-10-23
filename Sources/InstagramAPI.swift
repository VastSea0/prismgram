import Foundation

/// Typed wrappers around every Instagram `/api/v1/` endpoint used by the app.
///
/// Centralizing paths and request bodies here keeps `AppStore` free of raw endpoint strings and
/// gives a single place to update when an endpoint path or parameter changes.
@MainActor
struct InstagramAPI {
    let transport: any InstagramTransport

    // MARK: Feed & Stories

    func reelsTray() async throws -> [IGStoryTray] {
        let decoded = try await fetchDecoded(APIReelsTrayResponse.self, "/api/v1/feed/reels_tray/")
        return decoded.stories
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

    func reelsMedia(reelID: String) async throws -> [IGMediaItem] {
        let decoded = try await fetchDecoded(
            APIReelsMediaResponse.self,
            "/api/v1/feed/reels_media/",
            method: "POST",
            body: "reel_ids=\(Self.encode(reelID))"
        )
        return decoded.slides(for: reelID)
    }

    func storyViewers(mediaID: String) async throws -> (users: [IGUser], likedIDs: Set<String>, count: Int?) {
        let pk = mediaID.split(separator: "_").first.map(String.init) ?? mediaID
        let decoded = try await fetchDecoded(
            APIStoryViewersResponse.self,
            "/api/v1/media/\(Self.encode(pk))/list_reel_media_viewer/?include_blacklist_sample=true"
        )
        return decoded.parsedViewers
    }

    func mediaInfo(mediaID: String) async throws -> IGPost? {
        let pk = mediaID.split(separator: "_").first.map(String.init) ?? mediaID
        let decoded = try await fetchDecoded(
            APIMediaInfoResponse.self,
            "/api/v1/media/\(Self.encode(pk))/info/"
        )
        return decoded.firstPost
    }

    func mediaInfo(shortcode: String) async throws -> IGPost? {
        guard let pk = Self.mediaPK(fromShortcode: shortcode) else { return nil }
        return try await mediaInfo(mediaID: pk)
    }

    /// Converts an Instagram shortcode (`/p/<code>/` or `/reel/<code>/`) to its numeric media PK.
    static func mediaPK(fromShortcode shortcode: String) -> String? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        let clean = String(shortcode.prefix(11))
        guard !clean.isEmpty else { return nil }
        var id: UInt64 = 0
        for ch in clean {
            guard let idx = alphabet.firstIndex(of: ch) else { return nil }
            id = (id &* 64) &+ UInt64(idx)
        }
        return id > 0 ? String(id) : nil
    }

    // MARK: Explore, Reels, Search & Activity

    func exploreGrid() async throws -> [IGPost] {
        let decoded = try await fetchDecoded(APIExploreResponse.self, "/api/v1/discover/web/explore_grid/")
        return decoded.posts
    }

    func clipsDiscover(cursor: String? = nil) async throws -> APIClipsDiscoverResponse {
        var body = "page_size=8&include_feed_video=true"
        if let cursor {
            body += "&max_id=\(Self.encode(cursor))"
        }
        return try await fetchDecoded(APIClipsDiscoverResponse.self, "/api/v1/clips/discover/", method: "POST", body: body)
    }

    func topSearch(query: String) async throws -> APITopSearchResponse {
        try await fetchDecoded(
            APITopSearchResponse.self,
            "/api/v1/web/search/topsearch/?context=blended&query=\(Self.encode(query))&include_reel=true"
        )
    }

    func newsInbox() async throws -> [IGActivity] {
        let decoded = try await fetchDecoded(APINewsInboxResponse.self, "/api/v1/news/inbox/")
        return decoded.activities
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

    func createNote(text: String, closeFriends: Bool) async -> APICreateNoteResponse? {
        let path = "/api/v1/notes/create_note/"
        guard let response = try? await transport.request(
            path,
            method: "POST",
            body: "note_style=0&text=\(Self.encode(text))&audience=\(closeFriends ? 1 : 0)"
        ),
        (200..<300).contains(response.status),
        let data = response.data,
        let decoded = try? APIDecoding.decode(APICreateNoteResponse.self, from: data, endpoint: path),
        decoded.status == "ok" else { return nil }
        return decoded
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

    func currentUser() async -> String? {
        let path = "/api/v1/accounts/current_user/?edit=true"
        guard let response = try? await transport.request(path),
              (200..<300).contains(response.status),
              let data = response.data,
              let decoded = try? APIDecoding.decode(APICurrentUserResponse.self, from: data, endpoint: path),
              let name = decoded.user?.username, !name.isEmpty else { return nil }
        return name
    }

    func setFollowing(userID: String, follow: Bool) async throws -> APIFriendshipStatus? {
        let decoded = try await fetchDecoded(
            APIFriendshipMutationResponse.self,
            "/api/v1/friendships/\(follow ? "create" : "destroy")/\(userID)/",
            method: "POST",
            body: "container_module=profile&user_id=\(Self.encode(userID))"
        )
        return decoded.friendship_status
    }

    func friendshipList(userID: String, kind: FollowListKind, cursor: String?) async throws -> ([IGUser], String?) {
        var path = "/api/v1/friendships/\(userID)/\(kind.rawValue)/?count=24"
        if kind == .followers { path += "&search_surface=follow_list_page" }
        if let cursor { path += "&max_id=\(Self.encode(cursor))" }
        let decoded = try await fetchDecoded(APIFriendshipListResponse.self, path)
        return (decoded.parsedUsers, decoded.nextCursor)
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
        let response = try await transport.mutateMedia(action: liked ? "like" : "unlike", postID: postID)
        if response.status == 401 { throw Failure.unauthorized }
        guard (200..<300).contains(response.status),
              (response.json?["errors"] as? [Any])?.isEmpty != false else {
            throw Failure.rejected("Beğeni işlemi tamamlanamadı (HTTP \(response.status)).")
        }
    }

    func setSaved(postID: String, saved: Bool) async throws {
        let response = try await transport.mutateMedia(action: saved ? "save" : "unsave", postID: postID)
        if response.status == 401 { throw Failure.unauthorized }
        guard (200..<300).contains(response.status),
              (response.json?["errors"] as? [Any])?.isEmpty != false else {
            throw Failure.rejected("Kaydetme işlemi tamamlanamadı (HTTP \(response.status)).")
        }
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
