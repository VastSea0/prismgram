import Foundation

/// `Decodable` wire types for Instagram's `/api/v1/` responses.
///
/// Instagram's JSON mixes strings and numbers for IDs, counts and timestamps, and individual list
/// items can be malformed or ad placeholders. The helper wrappers below absorb those quirks while
/// still letting `JSONDecoder` validate the response structure and report exact `codingPath`s on
/// schema drift. Domain models in `Models.swift` remain unchanged.
enum APIDecoding {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data, endpoint: String) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as DecodingError {
            InstagramClient.debugLog("decode failed for \(endpoint) at \( describe(error) )")
            throw error
        } catch {
            InstagramClient.debugLog("decode failed for \(endpoint): \(error.localizedDescription)")
            throw error
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let ctx):
            return pathString(ctx.codingPath + [key]) + " (missing key)"
        case .typeMismatch(let type, let ctx):
            return pathString(ctx.codingPath) + " (expected \(type))"
        case .valueNotFound(let type, let ctx):
            return pathString(ctx.codingPath) + " (null \(type))"
        case .dataCorrupted(let ctx):
            return pathString(ctx.codingPath) + " (corrupted)"
        @unknown default:
            return "unknown"
        }
    }

    private static func pathString(_ path: [CodingKey]) -> String {
        path.isEmpty ? "<root>" : path.map(\.stringValue).joined(separator: ".")
    }
}

// MARK: - Coercing scalar wrappers

/// Decodes a JSON string or number as a non-empty `String`.
struct FlexString: Decodable {
    let value: String

    init?(optional value: String?) {
        guard let value, !value.isEmpty else { return nil }
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self), !text.isEmpty {
            self.value = text
        } else if let intVal = try? container.decode(Int64.self) {
            self.value = String(intVal)
        } else if let doubleVal = try? container.decode(Double.self) {
            self.value = String(doubleVal)
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected non-empty string or number")
            )
        }
    }
}

/// Decodes a JSON integer, floating-point number or numeric string as `Int`.
struct FlexInt: Decodable {
    let value: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self.value = intVal
        } else if let text = try? container.decode(String.self), let parsed = Int(text) {
            self.value = parsed
        } else if let doubleVal = try? container.decode(Double.self) {
            self.value = Int(doubleVal)
        } else {
            throw DecodingError.typeMismatch(
                Int.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected int or numeric string")
            )
        }
    }
}

/// Decodes a JSON number or numeric string as `Double`.
struct FlexDouble: Decodable {
    let value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let doubleVal = try? container.decode(Double.self) {
            self.value = doubleVal
        } else if let intVal = try? container.decode(Int64.self) {
            self.value = Double(intVal)
        } else if let text = try? container.decode(String.self), let parsed = Double(text) {
            self.value = parsed
        } else {
            throw DecodingError.typeMismatch(
                Double.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected double or numeric string")
            )
        }
    }
}

/// Decodes a JSON boolean or `0`/`1` number as `Bool`.
struct FlexBool: Decodable {
    let value: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self) {
            self.value = b
        } else if let n = try? container.decode(Int.self) {
            self.value = n != 0
        } else {
            throw DecodingError.typeMismatch(
                Bool.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected bool or int")
            )
        }
    }
}

/// Decodes an array while skipping elements that fail to decode (e.g. non-media feed rows),
/// debug-logging the element path when an element is skipped for a unexpected reason.
struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]

    private struct AnyDecodable: Decodable {}

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var results: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                results.append(element)
            } else {
                _ = try? container.decode(AnyDecodable.self)
            }
        }
        self.elements = results
    }
}

// MARK: - Shared wire objects

struct APIUser: Decodable {
    let pk: FlexString?
    let pk_id: FlexString?
    let id: FlexString?
    let username: String
    let full_name: String?
    let profile_pic_url: String?
    let profile_pic_url_hd: String?
    let hd_profile_pic_url_info: URLHolder?
    let is_verified: FlexBool?
    let biography: String?
    let external_url: String?
    let follower_count: FlexInt?
    let following_count: FlexInt?
    let media_count: FlexInt?
    let is_private: FlexBool?
    let friendship_status: APIFriendshipStatus?
    let category: String?

    struct URLHolder: Decodable {
        let url: String?
    }

    var domainModel: IGUser? {
        guard let resolvedID = (pk ?? pk_id ?? id)?.value else { return nil }
        return IGUser(
            id: resolvedID,
            username: username,
            fullName: full_name ?? "",
            avatarURL: IGJSON.url(hd_profile_pic_url_info?.url)
                ?? IGJSON.url(profile_pic_url_hd)
                ?? IGJSON.url(profile_pic_url),
            isVerified: is_verified?.value ?? false,
            biography: biography ?? "",
            externalURL: IGJSON.url(external_url),
            followerCount: follower_count?.value,
            followingCount: following_count?.value,
            mediaCount: media_count?.value,
            isPrivate: is_private?.value ?? false,
            isFollowing: friendship_status?.following?.value,
            isRequested: friendship_status?.outgoing_request?.value ?? false,
            followsViewer: friendship_status?.followed_by?.value ?? false,
            category: category.flatMap { $0.isEmpty ? nil : $0 }
        )
    }
}

struct APIFriendshipStatus: Decodable {
    let following: FlexBool?
    let outgoing_request: FlexBool?
    let followed_by: FlexBool?
}

struct APIMediaCandidate: Decodable {
    let url: String?
    let width: FlexInt?
    let height: FlexInt?
}

struct APIMedia: Decodable {
    let pk: FlexString?
    let id: FlexString?
    let code: String?
    let user: APIUser?
    let image_versions2: ImageVersions?
    let display_uri: String?
    let display_url: String?
    let video_versions: [APIMediaCandidate]?
    let original_width: FlexDouble?
    let original_height: FlexDouble?
    let taken_at: FlexDouble?
    let video_duration: FlexDouble?
    let carousel_media: [APIMedia]?
    let caption: Caption?
    let location: Location?
    let like_count: FlexInt?
    let comment_count: FlexInt?
    let has_liked: FlexBool?
    let has_viewer_saved: FlexBool?
    let play_count: FlexInt?
    let ig_play_count: FlexInt?
    let view_count: FlexInt?
    let timeline_pinned_user_ids: [FlexString]?
    let ad_id: FlexString?
    let injected: AnyObjectMarker?

    struct ImageVersions: Decodable {
        let candidates: [APIMediaCandidate]?
    }
    struct Caption: Decodable {
        let text: String?
    }
    struct Location: Decodable {
        let name: String?
    }
    struct AnyObjectMarker: Decodable {}

    var isSponsored: Bool { ad_id != nil || injected != nil }

    var mediaItem: IGMediaItem? {
        var thumb: URL?
        var full: URL?
        if let candidates = image_versions2?.candidates, !candidates.isEmpty {
            let sorted = candidates.sorted { ($0.width?.value ?? 0) > ($1.width?.value ?? 0) }
            full = IGJSON.url(sorted.first?.url)
            let chosenThumb = sorted.last(where: { ($0.width?.value ?? 0) >= 360 }) ?? sorted.last
            thumb = IGJSON.url(chosenThumb?.url)
        }
        if full == nil {
            full = IGJSON.url(display_uri) ?? IGJSON.url(display_url)
            thumb = thumb ?? full
        }
        let video = IGJSON.url(video_versions?.first?.url)
        guard full != nil || video != nil else { return nil }

        let width = original_width?.value ?? 0
        let height = original_height?.value ?? 0
        let ratio = (width > 0 && height > 0) ? min(max(width / height, 0.56), 1.91) : 1.0

        return IGMediaItem(
            id: (pk ?? id)?.value ?? UUID().uuidString,
            thumbURL: thumb ?? full,
            imageURL: full,
            videoURL: video,
            aspectRatio: ratio,
            takenAt: taken_at.map { Date(timeIntervalSince1970: $0.value) },
            duration: video_duration?.value
        )
    }

    var post: IGPost? {
        guard let author = user?.domainModel,
              let resolvedID = (pk ?? id)?.value else { return nil }

        let items: [IGMediaItem]
        if let carousel = carousel_media, !carousel.isEmpty {
            items = carousel.compactMap(\.mediaItem)
        } else if let single = mediaItem {
            items = [single]
        } else {
            return nil
        }
        guard !items.isEmpty else { return nil }

        let taken = taken_at.map { Date(timeIntervalSince1970: $0.value) } ?? .now
        return IGPost(
            id: resolvedID,
            code: code ?? resolvedID,
            user: author,
            locationName: location?.name,
            items: items,
            caption: caption?.text ?? "",
            takenAt: taken,
            likeCount: like_count?.value ?? 0,
            commentCount: comment_count?.value ?? 0,
            hasLiked: has_liked?.value ?? false,
            hasSaved: has_viewer_saved?.value ?? false,
            viewCount: (play_count ?? ig_play_count ?? view_count)?.value,
            isPinned: !(timeline_pinned_user_ids ?? []).isEmpty
        )
    }
}

// MARK: - Timeline (`/api/v1/feed/timeline/`)

struct APITimelineResponse: Decodable {
    let feed_items: LossyArray<FeedItem>?
    let next_max_id: FlexString?

    struct FeedItem: Decodable {
        let media_or_ad: APIMedia?
    }

    var posts: [IGPost] {
        (feed_items?.elements ?? []).compactMap { wrapper in
            guard let media = wrapper.media_or_ad, !media.isSponsored else { return nil }
            return media.post
        }
    }

    var nextCursor: String? { next_max_id?.value }
}

// MARK: - Comments (`/api/v1/media/<id>/comments/` & `/api/v1/web/comments/<id>/add/`)

struct APIComment: Decodable {
    let pk: FlexString?
    let id: FlexString?
    let text: String?
    let user: APIUser?
    let created_at: FlexDouble?
    let comment_like_count: FlexInt?

    var domainModel: IGComment? {
        guard let resolvedID = (pk ?? id)?.value,
              let text,
              let author = user?.domainModel else { return nil }
        return IGComment(
            id: resolvedID,
            user: author,
            text: text,
            createdAt: created_at.map { Date(timeIntervalSince1970: $0.value) } ?? .now,
            likeCount: comment_like_count?.value ?? 0
        )
    }
}

struct APICommentsResponse: Decodable {
    let comments: LossyArray<APIComment>?

    var items: [IGComment] {
        (comments?.elements ?? []).compactMap(\.domainModel)
    }
}

struct APIAddCommentResponse: Decodable {
    let comment: APIComment?
    let pk: FlexString?
    let id: FlexString?
    let text: String?
    let user: APIUser?
    let created_at: FlexDouble?
    let comment_like_count: FlexInt?

    var createdComment: IGComment? {
        if let wrapped = comment?.domainModel { return wrapped }
        return APIComment(
            pk: pk,
            id: id,
            text: text,
            user: user,
            created_at: created_at,
            comment_like_count: comment_like_count
        ).domainModel
    }
}
