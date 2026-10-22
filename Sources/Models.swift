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
        case .reels: return "play.rectangle"
        case .activity: return "heart"
        case .direct: return "paperplane"
        case .profile: return "person.crop.circle"
        }
    }

    var filledSymbolName: String {
        switch self {
        case .home: return "house.fill"
        case .explore: return "magnifyingglass"
        case .reels: return "play.rectangle.fill"
        case .activity: return "heart.fill"
        case .direct: return "paperplane.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }
}

// MARK: - Domain models (all values come from the signed-in account's own responses)

struct IGUser: Identifiable, Hashable, Sendable {
    let id: String
    var username: String
    var fullName: String
    var avatarURL: URL?
    var isVerified: Bool
    var biography: String = ""
    var followerCount: Int?
    var followingCount: Int?
    var mediaCount: Int?
}

struct IGMediaItem: Identifiable, Hashable, Sendable {
    let id: String
    let thumbURL: URL?
    let imageURL: URL?
    let videoURL: URL?
    let aspectRatio: Double
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
    let slides: [IGMediaItem]
}

struct IGActivity: Identifiable, Hashable, Sendable {
    let id: String
    let text: String
    let avatarURL: URL?
    let thumbURL: URL?
    let date: Date?
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

    static func url(_ value: Any?) -> URL? {
        guard let text = value as? String else { return nil }
        return URL(string: text)
    }

    static func user(_ dict: [String: Any]) -> IGUser? {
        guard let username = dict["username"] as? String,
              let id = string(dict["pk"]) ?? string(dict["pk_id"]) ?? string(dict["id"]) else { return nil }
        return IGUser(
            id: id,
            username: username,
            fullName: (dict["full_name"] as? String) ?? "",
            avatarURL: url(dict["profile_pic_url"]),
            isVerified: (dict["is_verified"] as? Bool) ?? false,
            biography: (dict["biography"] as? String) ?? "",
            followerCount: int(dict["follower_count"]),
            followingCount: int(dict["following_count"]),
            mediaCount: int(dict["media_count"])
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
        var video: URL?
        if let versions = dict["video_versions"] as? [[String: Any]] {
            video = url(versions.first?["url"])
        }
        guard full != nil || video != nil else { return nil }

        let width = double(dict["original_width"]) ?? 0
        let height = double(dict["original_height"]) ?? 0
        let ratio = (width > 0 && height > 0) ? min(max(width / height, 0.56), 1.91) : 1.0

        return IGMediaItem(
            id: string(dict["pk"]) ?? string(dict["id"]) ?? UUID().uuidString,
            thumbURL: thumb ?? full,
            imageURL: full,
            videoURL: video,
            aspectRatio: ratio
        )
    }

    static func post(_ dict: [String: Any]) -> IGPost? {
        guard let userDict = dict["user"] as? [String: Any],
              let user = user(userDict),
              let id = string(dict["pk"]) ?? string(dict["id"]) else { return nil }

        var items: [IGMediaItem] = []
        if let carousel = dict["carousel_media"] as? [[String: Any]] {
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
            hasLiked: (dict["has_liked"] as? Bool) ?? false,
            hasSaved: (dict["has_viewer_saved"] as? Bool) ?? false
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
        return IGStoryTray(id: user.id, user: user, hasUnseen: seen < latest, slides: slides)
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
