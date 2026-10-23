import AppKit
import Foundation

// MARK: - Layout & navigation

enum AppLayoutMode: String, CaseIterable, Identifiable, Sendable {
    case phone
    case hybrid
    case desktop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .phone: return "Telefon"
        case .hybrid: return "Hibrit"
        case .desktop: return "Masaüstü"
        }
    }

    var symbolName: String {
        switch self {
        case .phone: return "iphone"
        case .hybrid: return "sidebar.left"
        case .desktop: return "macwindow"
        }
    }

    var targetSize: NSSize {
        switch self {
        case .phone: return NSSize(width: 430, height: 880)
        case .hybrid: return NSSize(width: 1000, height: 860)
        case .desktop: return NSSize(width: 1400, height: 920)
        }
    }

    var minSize: NSSize {
        switch self {
        case .phone: return NSSize(width: 390, height: 700)
        case .hybrid: return NSSize(width: 820, height: 640)
        case .desktop: return NSSize(width: 1120, height: 700)
        }
    }
}

enum InstagramTab: String, CaseIterable, Identifiable, Sendable {
    case home
    case explore
    case reels
    case activity
    case direct
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Ana Sayfa"
        case .explore: return "Keşfet"
        case .reels: return "Reels"
        case .activity: return "Bildirimler"
        case .direct: return "Mesajlar"
        case .profile: return "Profil"
        }
    }

    var symbolName: String {
        switch self {
        case .home: return "house"
        case .explore: return "magnifyingglass"
        case .reels: return "play.square"
        case .activity: return "heart"
        case .direct: return "paperplane"
        case .profile: return "person.crop.circle"
        }
    }

    var filledSymbolName: String {
        switch self {
        case .home: return "house.fill"
        case .explore: return "magnifyingglass"
        case .reels: return "play.square.fill"
        case .activity: return "heart.fill"
        case .direct: return "paperplane.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }
}

enum ProfileSection: String, CaseIterable, Identifiable, Sendable {
    case posts
    case reels
    case tagged
    case saved

    var id: String { rawValue }

    var title: String {
        switch self {
        case .posts: return "Gönderiler"
        case .reels: return "Reels"
        case .tagged: return "Etiketlenenler"
        case .saved: return "Kaydedilenler"
        }
    }

    var symbolName: String {
        switch self {
        case .posts: return "squareshape.split.3x3"
        case .reels: return "play.rectangle"
        case .tagged: return "person.crop.square"
        case .saved: return "bookmark"
        }
    }

    /// The instagram.com route that shows this grid.
    func path(for username: String) -> String {
        switch self {
        case .posts: return "/\(username)/"
        case .reels: return "/\(username)/reels/"
        case .tagged: return "/\(username)/tagged/"
        case .saved: return "/\(username)/saved/all-posts/"
        }
    }

    var filledSymbolName: String {
        switch self {
        case .posts: return "squareshape.split.3x3"
        case .reels: return "play.rectangle.fill"
        case .tagged: return "person.crop.square.fill"
        case .saved: return "bookmark.fill"
        }
    }
}

enum FollowListKind: String, Identifiable, Sendable {
    case followers
    case following

    var id: String { rawValue }
    var title: String { self == .followers ? "Takipçiler" : "Takip Edilenler" }
}

// MARK: - Domain models (all values come from the signed-in account's own responses)

struct IGUser: Identifiable, Hashable, Sendable {
    let id: String
    var username: String
    var fullName: String
    var avatarURL: URL?
    var isVerified: Bool
    var biography: String = ""
    var externalURL: URL? = nil
    var followerCount: Int?
    var followingCount: Int?
    var mediaCount: Int?
    var isPrivate: Bool = false
    var isFollowing: Bool? = nil
    var isRequested: Bool = false
    var followsViewer: Bool = false
    var category: String? = nil
    var mutualFollowers: [String] = []
    var mutualFollowerCount: Int = 0

    /// Fills the gaps in a freshly fetched user with what an older, partial copy already knew.
    func merged(over older: IGUser?) -> IGUser {
        guard let older, older.id == id else { return self }
        var result = self
        if result.avatarURL == nil { result.avatarURL = older.avatarURL }
        if result.fullName.isEmpty { result.fullName = older.fullName }
        if result.followerCount == nil { result.followerCount = older.followerCount }
        if result.followingCount == nil { result.followingCount = older.followingCount }
        if result.mediaCount == nil { result.mediaCount = older.mediaCount }
        if result.isFollowing == nil { result.isFollowing = older.isFollowing }
        if result.biography.isEmpty { result.biography = older.biography }
        if result.externalURL == nil { result.externalURL = older.externalURL }
        return result
    }
}

struct IGMediaItem: Identifiable, Hashable, Sendable {
    let id: String
    let thumbURL: URL?
    let imageURL: URL?
    let videoURL: URL?
    let aspectRatio: Double
    var takenAt: Date? = nil
    /// Seconds, for videos.
    var duration: Double? = nil
    /// Story viewer count and viewers list (present on the signed-in viewer's own stories).
    var viewerCount: Int? = nil
    var viewers: [IGUser] = []
    var likedViewerIDs: Set<String> = []
}

struct IGPost: Identifiable, Hashable, Sendable {
    let id: String
    let code: String
    var user: IGUser
    let locationName: String?
    let items: [IGMediaItem]
    let caption: String
    let takenAt: Date
    var likeCount: Int
    var commentCount: Int
    var hasLiked: Bool
    var hasSaved: Bool
    var viewCount: Int? = nil
    var isPinned: Bool = false

    var isVideo: Bool { items.first?.videoURL != nil }
}

struct IGComment: Identifiable, Hashable, Sendable {
    let id: String
    let user: IGUser
    let text: String
    let createdAt: Date
    var likeCount: Int
}

struct IGStoryTray: Identifiable, Hashable, Sendable {
    let id: String
    let user: IGUser
    var hasUnseen: Bool
    var slides: [IGMediaItem]
    var title: String? = nil
    var coverURL: URL? = nil
    /// When the viewer last watched this tray (seconds since 1970), used to resume at the first new slide.
    var seenAt: Double = 0

    /// Index of the first slide posted after the viewer last watched, or 0 when everything is new or seen.
    var resumeIndex: Int {
        guard hasUnseen, seenAt > 0 else { return 0 }
        return slides.firstIndex(where: { ($0.takenAt?.timeIntervalSince1970 ?? 0) > seenAt }) ?? 0
    }
}

struct IGActivity: Identifiable, Hashable, Sendable {
    let id: String
    let text: String
    let avatarURL: URL?
    let thumbURL: URL?
    let date: Date?
}

struct IGNote: Identifiable, Hashable, Sendable {
    let id: String
    let user: IGUser
    let text: String
    let musicTitle: String?
    let musicArtist: String?
    let createdAt: Date
    var musicPreviewURL: URL? = nil
    var musicCoverURL: URL? = nil
    /// The note's own id (for deleting the viewer's note), as opposed to the tray item id.
    var noteID: String? = nil
}

struct IGDirectMessage: Identifiable, Hashable, Sendable {
    enum Delivery: Hashable, Sendable { case sent, sending, failed }

    let id: String
    let senderFBID: String
    let senderUsername: String?
    let senderAvatarURL: URL?
    var text: String
    let timestamp: Date
    let isFromViewer: Bool
    /// A photo, video or shared post's preview attached to the message.
    var media: IGMediaItem? = nil
    /// Emoji reactions left on the message.
    var reactions: [String] = []
    var delivery: Delivery = .sent
    var kind: Kind = .text
    /// What a shared reel, post or story points at.
    var share: SharePreview? = nil
    /// The message this one replies to.
    var replyTo: ReplyQuote? = nil
    /// The direct_v2 item id, when the response carries one (needed to react through the API).
    var itemID: String? = nil
    /// Playable audio for voice messages.
    var audioURL: URL? = nil

    enum Kind: String, Hashable, Sendable {
        case text, photo, video, reel, post, story, storyReply, voice, sticker, link, like

        /// Short label Instagram shows for the kind of thing that was sent.
        var label: String {
            switch self {
            case .text: return "Mesaj"
            case .photo: return "Fotoğraf"
            case .video: return "Video"
            case .reel: return "Reels"
            case .post: return "Gönderi"
            case .story: return "Hikaye"
            case .storyReply: return "Hikaye yanıtı"
            case .voice: return "Sesli mesaj"
            case .sticker: return "Çıkartma"
            case .link: return "Bağlantı"
            case .like: return "Beğeni"
            }
        }

        var symbolName: String {
            switch self {
            case .reel: return "play.rectangle.on.rectangle.fill"
            case .post: return "square.grid.3x3.fill"
            case .story, .storyReply: return "circle.dashed"
            case .video: return "video.fill"
            case .photo: return "photo.fill"
            case .voice: return "waveform"
            case .link: return "link"
            default: return "bubble.left.fill"
            }
        }
    }

    struct SharePreview: Hashable, Sendable {
        var title: String?
        var subtitle: String?
        var avatarURL: URL?
        var url: URL?
    }

    struct ReplyQuote: Hashable, Sendable {
        var text: String
        var senderUsername: String?
        var isFromViewer: Bool
    }
}

struct IGDirectThread: Identifiable, Hashable, Sendable {
    let id: String
    let threadFBID: String
    let title: String
    let users: [IGUser]
    let isGroup: Bool
    let isPinned: Bool
    var isUnread: Bool
    var lastActivityAt: Date
    var snippet: String
    var viewerFBID: String
    var messages: [IGDirectMessage]
    var hasOlderMessages: Bool = false
}

// MARK: - Parsing

enum IGJSON {
    static func string(_ value: Any?) -> String? {
        if let text = value as? String, !text.isEmpty { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }

    static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }

    static func bool(_ value: Any?) -> Bool? {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return nil
    }

    static func url(_ value: Any?) -> URL? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return URL(string: text)
    }

    static func user(_ dict: [String: Any]) -> IGUser? {
        guard let username = dict["username"] as? String,
              let id = string(dict["pk"]) ?? string(dict["pk_id"]) ?? string(dict["id"]) else { return nil }
        let hdAvatar = (dict["hd_profile_pic_url_info"] as? [String: Any])?["url"]
        let friendship = dict["friendship_status"] as? [String: Any]
        return IGUser(
            id: id,
            username: username,
            fullName: (dict["full_name"] as? String) ?? "",
            avatarURL: url(hdAvatar) ?? url(dict["profile_pic_url_hd"]) ?? url(dict["profile_pic_url"]),
            isVerified: bool(dict["is_verified"]) ?? false,
            biography: (dict["biography"] as? String) ?? "",
            externalURL: url(dict["external_url"]),
            followerCount: int(dict["follower_count"]),
            followingCount: int(dict["following_count"]),
            mediaCount: int(dict["media_count"]),
            isPrivate: bool(dict["is_private"]) ?? false,
            isFollowing: bool(friendship?["following"]),
            isRequested: bool(friendship?["outgoing_request"]) ?? false,
            followsViewer: bool(friendship?["followed_by"]) ?? false,
            category: (dict["category"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    /// The user object returned by `/api/v1/users/web_profile_info/`, which uses GraphQL field names.
    static func graphUser(_ dict: [String: Any]) -> IGUser? {
        guard let username = dict["username"] as? String,
              let id = string(dict["id"]) ?? string(dict["pk"]) else { return nil }
        func count(_ key: String) -> Int? { int((dict[key] as? [String: Any])?["count"]) }
        let mutual = dict["edge_mutual_followed_by"] as? [String: Any]
        let mutualNames = ((mutual?["edges"] as? [[String: Any]]) ?? []).compactMap {
            ($0["node"] as? [String: Any])?["username"] as? String
        }
        let bioLink = ((dict["bio_links"] as? [[String: Any]])?.first)?["url"]
        return IGUser(
            id: id,
            username: username,
            fullName: (dict["full_name"] as? String) ?? "",
            avatarURL: url(dict["profile_pic_url_hd"]) ?? url(dict["profile_pic_url"]),
            isVerified: bool(dict["is_verified"]) ?? false,
            biography: (dict["biography"] as? String) ?? "",
            externalURL: url(dict["external_url"]) ?? url(bioLink),
            followerCount: count("edge_followed_by"),
            followingCount: count("edge_follow"),
            mediaCount: count("edge_owner_to_timeline_media"),
            isPrivate: bool(dict["is_private"]) ?? false,
            isFollowing: bool(dict["followed_by_viewer"]),
            isRequested: bool(dict["requested_by_viewer"]) ?? false,
            followsViewer: bool(dict["follows_viewer"]) ?? false,
            category: (dict["category_name"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            mutualFollowers: mutualNames,
            mutualFollowerCount: int(mutual?["count"]) ?? mutualNames.count
        )
    }

    static func mediaItem(_ dict: [String: Any]) -> IGMediaItem? {
        var thumb: URL?
        var full: URL?
        if let versions = dict["image_versions2"] as? [String: Any],
           let candidates = versions["candidates"] as? [[String: Any]], !candidates.isEmpty {
            let sorted = candidates.sorted { (int($0["width"]) ?? 0) > (int($1["width"]) ?? 0) }
            full = url(sorted.first?["url"])
            thumb = url((sorted.last(where: { (int($0["width"]) ?? 0) >= 360 }) ?? sorted.last)?["url"])
        }
        if full == nil {
            full = url(dict["display_uri"]) ?? url(dict["display_url"])
            thumb = thumb ?? full
        }
        var video: URL?
        if let versions = dict["video_versions"] as? [[String: Any]] {
            video = url(versions.first?["url"])
        }
        guard full != nil || video != nil else { return nil }

        let width = double(dict["original_width"]) ?? 0
        let height = double(dict["original_height"]) ?? 0
        let ratio = (width > 0 && height > 0) ? min(max(width / height, 0.56), 1.91) : 1.0

        let rawViewers = (dict["viewers"] as? [[String: Any]])
            ?? (dict["users"] as? [[String: Any]])
            ?? (((dict["edge_story_media_viewers"] as? [String: Any])?["edges"] as? [[String: Any]])?.compactMap { $0["node"] as? [String: Any] })
            ?? []
        var viewers: [IGUser] = []
        var likedViewerIDs = Set<String>()
        for entry in rawViewers {
            let userDict = (entry["user"] as? [String: Any]) ?? entry
            if let parsedUser = user(userDict) ?? graphUser(userDict) {
                viewers.append(parsedUser)
                if bool(entry["has_liked"]) == true {
                    likedViewerIDs.insert(parsedUser.id)
                }
            }
        }
        let edgeCount = int((dict["edge_story_media_viewers"] as? [String: Any])?["count"])
        let viewerCount = int(dict["total_viewer_count"])
            ?? int(dict["viewer_count"])
            ?? int(dict["user_count"])
            ?? int(dict["fb_viewer_count"])
            ?? edgeCount
            ?? (viewers.isEmpty ? nil : viewers.count)

        return IGMediaItem(
            id: string(dict["pk"]) ?? string(dict["id"]) ?? UUID().uuidString,
            thumbURL: thumb ?? full,
            imageURL: full,
            videoURL: video,
            aspectRatio: ratio,
            takenAt: double(dict["taken_at"]).map { Date(timeIntervalSince1970: $0) },
            duration: double(dict["video_duration"]),
            viewerCount: viewerCount,
            viewers: viewers,
            likedViewerIDs: likedViewerIDs
        )
    }

    static func post(_ dict: [String: Any]) -> IGPost? {
        guard let userDict = dict["user"] as? [String: Any],
              let user = user(userDict),
              let id = string(dict["pk"]) ?? string(dict["id"]) else { return nil }

        var items: [IGMediaItem] = []
        if let carousel = dict["carousel_media"] as? [[String: Any]], !carousel.isEmpty {
            items = carousel.compactMap(mediaItem)
        } else if let single = mediaItem(dict) {
            items = [single]
        }
        guard !items.isEmpty else { return nil }

        let caption = ((dict["caption"] as? [String: Any])?["text"] as? String) ?? ""
        let location = (dict["location"] as? [String: Any])?["name"] as? String
        let takenAt = double(dict["taken_at"]).map { Date(timeIntervalSince1970: $0) } ?? .now

        return IGPost(
            id: id,
            code: (dict["code"] as? String) ?? id,
            user: user,
            locationName: location,
            items: items,
            caption: caption,
            takenAt: takenAt,
            likeCount: int(dict["like_count"]) ?? 0,
            commentCount: int(dict["comment_count"]) ?? 0,
            hasLiked: bool(dict["has_liked"]) ?? false,
            hasSaved: bool(dict["has_viewer_saved"]) ?? false,
            viewCount: int(dict["play_count"]) ?? int(dict["ig_play_count"]) ?? int(dict["view_count"]),
            isPinned: !((dict["timeline_pinned_user_ids"] as? [Any]) ?? []).isEmpty
        )
    }

    /// Walks arbitrary response trees and returns every media object, in document order.
    static func collectPosts(in value: Any) -> [IGPost] {
        var result: [IGPost] = []
        var seen = Set<String>()
        func walk(_ node: Any) {
            if let dict = node as? [String: Any] {
                let looksLikeMedia = dict["code"] != nil
                    && dict["user"] is [String: Any]
                    && (dict["image_versions2"] != nil || dict["video_versions"] != nil || dict["carousel_media"] != nil)
                if looksLikeMedia, let parsed = post(dict) {
                    if seen.insert(parsed.id).inserted { result.append(parsed) }
                    return
                }
                for key in dict.keys.sorted() { if let child = dict[key] { walk(child) } }
            } else if let array = node as? [Any] {
                array.forEach(walk)
            }
        }
        walk(value)
        return result
    }

    static func storyTray(_ dict: [String: Any]) -> IGStoryTray? {
        guard let userDict = dict["user"] as? [String: Any], let user = user(userDict) else { return nil }
        let rawItems = (dict["items"] as? [[String: Any]]) ?? []
        let slides = rawItems.compactMap(mediaItem)
        let latest = double(dict["latest_reel_media"]) ?? 0
        let seen = double(dict["seen"]) ?? 0
        let trayID = string(dict["id"]) ?? user.id
        let title = dict["title"] as? String
        let cover = ((dict["cover_media"] as? [String: Any])?["cropped_image_version"] as? [String: Any])?["url"]
        return IGStoryTray(
            id: trayID,
            user: user,
            hasUnseen: seen < latest,
            slides: slides,
            title: title,
            coverURL: url(cover),
            seenAt: seen
        )
    }

    /// Extracts story slides from a `/api/v1/feed/reels_media/` response for a given reel ID.
    static func storySlides(from json: [String: Any], reelID: String) -> [IGMediaItem] {
        if let reels = json["reels"] as? [String: Any],
           let reel = (reels[reelID] as? [String: Any]) ?? (reels.values.first as? [String: Any]),
           let items = reel["items"] as? [[String: Any]] {
            let parsed = items.compactMap(mediaItem)
            if !parsed.isEmpty { return parsed }
        }
        if let mediaList = json["reels_media"] as? [[String: Any]],
           let first = mediaList.first,
           let items = first["items"] as? [[String: Any]] {
            return items.compactMap(mediaItem)
        }
        return []
    }

    static func highlights(from json: [String: Any], fallbackUser: IGUser?) -> [IGStoryTray] {
        guard let data = json["data"] as? [String: Any],
              let highlights = data["highlights"] as? [String: Any],
              let edges = highlights["edges"] as? [[String: Any]] else { return [] }
        return edges.compactMap { edge in
            guard let node = edge["node"] as? [String: Any],
                  let id = string(node["id"]) else { return nil }
            let userDict = node["user"] as? [String: Any]
            let owner = (userDict.flatMap(user)) ?? fallbackUser
            guard let owner else { return nil }
            let title = (node["title"] as? String) ?? "Öne Çıkan"
            let cover = ((node["cover_media"] as? [String: Any])?["cropped_image_version"] as? [String: Any])?["url"]
            return IGStoryTray(
                id: id,
                user: owner,
                hasUnseen: false,
                slides: [],
                title: title,
                coverURL: url(cover) ?? owner.avatarURL
            )
        }
    }

    static func notes(from json: [String: Any]) -> [IGNote] {
        let data = (json["data"] as? [String: Any]) ?? json
        let container = (data["response"] as? [String: Any]) ?? data
        let items = (container["inbox_tray_items"] as? [[String: Any]])
            ?? (data["xdt_get_inbox_tray_items"] as? [String: Any])?["inbox_tray_items"] as? [[String: Any]]
            ?? []

        return items.compactMap { item in
            guard let noteDict = item["note_dict"] as? [String: Any] else { return nil }
            let text = (noteDict["text"] as? String) ?? ""
            let musicAsset = (((noteDict["note_response_info"] as? [String: Any])?["music_note_response_info"] as? [String: Any])?["music_info"] as? [String: Any])?["music_asset_info"] as? [String: Any]
            let musicTitle = musicAsset?["title"] as? String
            let musicArtist = musicAsset?["display_artist"] as? String
            guard !text.isEmpty || (musicTitle != nil && !musicTitle!.isEmpty) else { return nil }

            let pogUsers = ((item["pog_info"] as? [String: Any])?["pog_users"] as? [[String: Any]]) ?? []
            guard let firstUser = pogUsers.first, let author = user(firstUser) else { return nil }
            let id = string(item["inbox_tray_item_id"]) ?? author.id
            let created = double(noteDict["created_at"]).map { Date(timeIntervalSince1970: $0) } ?? .now
            return IGNote(
                id: id,
                user: author,
                text: text,
                musicTitle: musicTitle,
                musicArtist: musicArtist,
                createdAt: created,
                musicPreviewURL: url(musicAsset?["progressive_download_url"]) ?? url(musicAsset?["fast_start_progressive_download_url"]),
                musicCoverURL: url(musicAsset?["cover_artwork_thumbnail_uri"]) ?? url(musicAsset?["cover_artwork_uri"]),
                noteID: string(noteDict["id"])
            )
        }
    }

    static func directThreads(from json: [String: Any]) -> [IGDirectThread] {
        guard let data = json["data"] as? [String: Any],
              let mailbox = data["get_slide_mailbox_for_iris_subscription"] as? [String: Any] else { return [] }

        var rawThreads: [([String: Any], Bool)] = []
        if let pinned = mailbox["pinned_threads_v2"] as? [[String: Any]] {
            for entry in pinned {
                if let thread = entry["as_ig_direct_thread"] as? [String: Any] {
                    rawThreads.append((thread, true))
                }
            }
        }
        if let folder = mailbox["threads_by_folder"] as? [String: Any],
           let edges = folder["edges"] as? [[String: Any]] {
            for edge in edges {
                if let node = edge["node"] as? [String: Any],
                   let thread = node["as_ig_direct_thread"] as? [String: Any] {
                    rawThreads.append((thread, bool(thread["is_pin"]) ?? false))
                }
            }
        }

        var seen = Set<String>()
        var result: [IGDirectThread] = []
        for (dict, pinned) in rawThreads {
            guard let parsed = directThread(from: dict, isPinnedOverride: pinned) else { continue }
            if seen.insert(parsed.id).inserted {
                result.append(parsed)
            }
        }
        return result
    }

    static func directThreadDetail(
        from json: [String: Any],
        fallbackThread: IGDirectThread? = nil,
        viewerID: String = ""
    ) -> IGDirectThread? {
        guard let data = json["data"] as? [String: Any],
              let container = (data["get_slide_thread_nullable"] as? [String: Any])
                  ?? (data["fetch__SlideThread"] as? [String: Any]),
              let dict = container["as_ig_direct_thread"] as? [String: Any] else { return nil }
        return directThread(
            from: dict,
            isPinnedOverride: nil,
            fallbackThread: fallbackThread,
            fallbackViewerID: viewerID
        )
    }

    private static func directThread(
        from dict: [String: Any],
        isPinnedOverride: Bool?,
        fallbackThread: IGDirectThread? = nil,
        fallbackViewerID: String = ""
    ) -> IGDirectThread? {
        let rawID = string(dict["id"])?.replacingOccurrences(of: "XFBIGDirectViewerThread:", with: "")
            .replacingOccurrences(of: "SlideThread:", with: "")
        let threadID = string(dict["thread_id"])
            ?? string(dict["thread_key"])
            ?? fallbackThread?.id
            ?? rawID
        let threadFBID = string(dict["thread_fbid"])
            ?? fallbackThread?.threadFBID
            ?? rawID
            ?? threadID
        guard let id = threadID, let fbid = threadFBID else { return nil }

        let viewerDict = dict["viewer"] as? [String: Any]
        let viewerID = string(dict["viewer_id"])
            ?? string(viewerDict?["id"])
            ?? (!fallbackViewerID.isEmpty ? fallbackViewerID : (fallbackThread?.viewerFBID ?? ""))
        let viewerFBID = string(viewerDict?["interop_messaging_user_fbid"])
            ?? fallbackThread?.viewerFBID
            ?? viewerID

        let rawUsers = (dict["users"] as? [[String: Any]]) ?? []
        let allUsers = rawUsers.compactMap(user)
        let otherUsers = allUsers.filter { $0.id != viewerID }
        let parsedParticipants = otherUsers.isEmpty ? allUsers : otherUsers
        let participants = parsedParticipants.isEmpty ? (fallbackThread?.users ?? []) : parsedParticipants

        let rawTitle = (dict["thread_title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallbackTitle = participants.map { $0.fullName.isEmpty ? $0.username : $0.fullName }.joined(separator: ", ")
        let title = !rawTitle.isEmpty
            ? rawTitle
            : (!fallbackTitle.isEmpty ? fallbackTitle : (fallbackThread?.title ?? "Sohbet"))

        let lastMs = double(dict["last_activity_timestamp_ms"]) ?? 0
        let lastDate = lastMs > 0 ? Date(timeIntervalSince1970: lastMs / 1000.0) : (fallbackThread?.lastActivityAt ?? .now)

        var messages: [IGDirectMessage] = []
        var latestSnippet = ""
        var hasOlderMessages = false
        let slideMessages = (dict["slide_messages"] as? [String: Any])
            ?? (dict["slide_messages_before"] as? [String: Any])
            ?? (dict["slide_messages_after"] as? [String: Any])
        if let slideMessages {
            if let pageInfo = slideMessages["page_info"] as? [String: Any] {
                hasOlderMessages = bool(pageInfo["has_next_page"])
                    ?? bool(pageInfo["has_previous_page"])
                    ?? false
            }
            if let edges = slideMessages["edges"] as? [[String: Any]] {
                for edge in edges {
                    guard let node = edge["node"] as? [String: Any] else { continue }
                    if latestSnippet.isEmpty, let snippet = node["igd_snippet"] as? String, !snippet.isEmpty {
                        latestSnippet = snippet
                    }
                    guard let message = directMessage(node, viewerFBID: viewerFBID, viewerID: viewerID, fallbackMs: lastMs) else { continue }
                    if latestSnippet.isEmpty {
                        latestSnippet = message.text.isEmpty ? message.kind.label : message.text
                    }
                    messages.append(message)
                }
            }
        }

        messages.sort { $0.timestamp < $1.timestamp }

        return IGDirectThread(
            id: id,
            threadFBID: fbid,
            title: title,
            users: participants,
            isGroup: bool(dict["is_group"]) ?? fallbackThread?.isGroup ?? (participants.count > 1),
            isPinned: isPinnedOverride ?? (bool(dict["is_pin"]) ?? fallbackThread?.isPinned ?? false),
            isUnread: bool(dict["marked_as_unread"]) ?? fallbackThread?.isUnread ?? false,
            lastActivityAt: lastDate,
            snippet: latestSnippet,
            viewerFBID: viewerFBID,
            messages: messages,
            hasOlderMessages: hasOlderMessages
        )
    }

    /// Finds a photo, video or shared-post preview anywhere in a message node, without descending into the sender.
    static func attachment(in node: [String: Any]) -> IGMediaItem? {
        var found: IGMediaItem?
        func walk(_ value: Any, depth: Int) {
            guard found == nil, depth < 9 else { return }
            if let dict = value as? [String: Any] {
                if dict["image_versions2"] != nil || dict["video_versions"] != nil, let item = mediaItem(dict) {
                    found = item
                    return
                }
                for (key, child) in dict where !skippedAttachmentKeys.contains(key) {
                    walk(child, depth: depth + 1)
                }
            } else if let array = value as? [Any] {
                array.forEach { walk($0, depth: depth + 1) }
            }
        }
        walk(node, depth: 0)
        if let found { return found }

        // Shares and attachments that are not media objects still carry a preview image URL (and sometimes a playable video URL).
        var preview: (image: URL, video: URL?, ratio: Double)?
        var discoveredVideo: URL?
        func scan(_ value: Any, depth: Int) {
            guard depth < 9 else { return }
            if let dict = value as? [String: Any] {
                if discoveredVideo == nil {
                    for vKey in ["playable_url_quality_hd", "playable_url", "video_url"] {
                        if let vStr = dict[vKey] as? String, let vURL = URL(string: vStr), vURL.scheme?.hasPrefix("http") == true {
                            discoveredVideo = vURL
                            break
                        }
                    }
                    if discoveredVideo == nil,
                       let attStr = dict["attachment_cdn_url"] as? String,
                       let attURL = URL(string: attStr),
                       attURL.path.lowercased().hasSuffix(".mp4") || ((dict["__typename"] as? String) ?? "").lowercased().contains("video") {
                        discoveredVideo = attURL
                    }
                }
                guard preview == nil else {
                    for (key, child) in dict where !skippedAttachmentKeys.contains(key) {
                        scan(child, depth: depth + 1)
                    }
                    return
                }
                let typename = ((dict["__typename"] as? String) ?? "").lowercased()
                let isVideoAttachment = typename.contains("video")
                if let cdnPreview = (dict["preview_cdn_url"] as? String).flatMap(URL.init(string:))
                    ?? (dict["attachment_cdn_url"] as? String).flatMap(URL.init(string:)),
                   isMediaCDN(cdnPreview) || isVideoAttachment {
                    let rawAttachmentURL = (dict["attachment_cdn_url"] as? String).flatMap(URL.init(string:))
                    let videoURL = isVideoAttachment ? rawAttachmentURL : discoveredVideo
                    let imageURL = isMediaCDN(cdnPreview) ? cdnPreview : ((dict["preview_cdn_url"] as? String).flatMap(URL.init(string:)) ?? cdnPreview)
                    let width = double(dict["width"]) ?? double(dict["preview_width"]) ?? 0
                    let height = double(dict["height"]) ?? double(dict["preview_height"]) ?? 0
                    let ratio = width > 0 && height > 0 ? min(max(width / height, 0.56), 1.91) : 1
                    preview = (imageURL, videoURL, ratio)
                } else {
                    for key in ["preview_url", "image_url", "preview_image_url", "uri", "url"] {
                        if let text = dict[key] as? String, let link = URL(string: text), isMediaCDN(link) {
                            let width = double(dict["width"]) ?? double(dict["preview_width"]) ?? 0
                            let height = double(dict["height"]) ?? double(dict["preview_height"]) ?? 0
                            preview = (link, discoveredVideo, width > 0 && height > 0 ? min(max(width / height, 0.56), 1.91) : 1)
                            break
                        }
                    }
                }
                for (key, child) in dict where !skippedAttachmentKeys.contains(key) {
                    scan(child, depth: depth + 1)
                }
            } else if let array = value as? [Any] {
                array.forEach { scan($0, depth: depth + 1) }
            }
        }
        scan(node, depth: 0)
        return preview.map {
            IGMediaItem(
                id: $0.image.absoluteString,
                thumbURL: $0.image,
                imageURL: $0.image,
                videoURL: $0.video ?? discoveredVideo,
                aspectRatio: $0.ratio
            )
        }
    }

    static let skippedAttachmentKeys: Set<String> = ["sender", "replied_to_message", "user_dict", "profile_pic_url", "reactions"]

    static func isMediaCDN(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let path = url.path.lowercased()
        return (host.contains("cdninstagram.com") || host.contains("fbcdn.net"))
            && !path.hasSuffix(".mp4") && !path.contains("/t51.2885-19/")
    }

    static func describeContentType(_ type: String) -> String {
        let lower = type.lowercased()
        if lower.contains("reel") || lower.contains("clip") { return "Bir Reels videosu paylaştı" }
        if lower.contains("story") || lower.contains("montage") { return "Bir hikaye paylaştı" }
        if lower.contains("media") || lower.contains("photo") || lower.contains("image") { return "Bir medya gönderdi" }
        if lower.contains("voice") || lower.contains("audio") { return "Sesli mesaj" }
        if lower.contains("like") || lower.contains("reaction") { return "❤️" }
        if lower.contains("link") || lower.contains("xma") { return "Bir bağlantı paylaştı" }
        return ""
    }

    static func comment(_ dict: [String: Any]) -> IGComment? {
        guard let id = string(dict["pk"]),
              let text = dict["text"] as? String,
              let userDict = dict["user"] as? [String: Any],
              let user = user(userDict) else { return nil }
        return IGComment(
            id: id,
            user: user,
            text: text,
            createdAt: double(dict["created_at"]).map { Date(timeIntervalSince1970: $0) } ?? .now,
            likeCount: int(dict["comment_like_count"]) ?? 0
        )
    }

    static func activities(in json: [String: Any]) -> [IGActivity] {
        var stories: [[String: Any]] = []
        for key in ["new_stories", "old_stories"] {
            stories += (json[key] as? [[String: Any]]) ?? []
        }
        if stories.isEmpty, let aymf = json["stories"] as? [[String: Any]] { stories = aymf }

        return stories.enumerated().compactMap { index, story in
            guard let args = story["args"] as? [String: Any],
                  let text = args["text"] as? String, !text.isEmpty else { return nil }
            let media = (args["media"] as? [[String: Any]])?.first
            return IGActivity(
                id: string(story["pk"]) ?? "\(index)-\(text.hashValue)",
                text: text,
                avatarURL: url(args["profile_image"]),
                thumbURL: url(media?["image"]),
                date: double(args["timestamp"]).map { Date(timeIntervalSince1970: $0) }
            )
        }
    }
}
