import Foundation

// MARK: - Direct message parsing
//
// The web inbox (IGDThreadDetailQuery / PolarisDirectInboxQuery) describes each message with a
// `content_type`, a `content` object whose `__typename` names the kind, and XMA ("extensible message
// attachment") objects for shared reels, posts and stories. Field names are matched loosely because
// they differ between attachment types and change over time; run with PRISMGRAM_SCHEMA_DUMP to see
// the real shapes (see `SchemaDump`).

extension IGJSON {
    static func directMessage(_ node: [String: Any], viewerFBID: String, viewerID: String, fallbackMs: Double) -> IGDirectMessage? {
        let id = string(node["message_id"]) ?? string(node["id"]) ?? UUID().uuidString
        let sender = node["sender"] as? [String: Any]
        let senderDict = sender?["user_dict"] as? [String: Any]
        let senderFBID = string(node["sender_fbid"])
            ?? string(senderDict?["interop_messaging_user_fbid"])
            ?? string(sender?["id"])
            ?? ""
        let content = node["content"] as? [String: Any]
        let textBody = (node["text_body"] as? String) ?? (content?["text_body"] as? String) ?? ""
        let snippet = (node["igd_snippet"] as? String) ?? ""
        let contentType = (node["content_type"] as? String) ?? ""

        let media = attachment(in: node)
        let signature = ([contentType] + typeNames(in: content ?? node, depth: 0)).joined(separator: " ").lowercased()
        let kind = messageKind(signature: signature, media: media, text: textBody)
        let share = [.reel, .post, .story, .link].contains(kind) ? sharePreview(in: node) : nil

        var text = textBody
        if text.isEmpty && media == nil && share == nil {
            text = kind == .like ? "❤️" : (!snippet.isEmpty ? snippet : describeContentType(contentType))
        }
        guard !text.isEmpty || media != nil || share != nil || kind == .voice else { return nil }

        let ms = double(node["timestamp_ms"]) ?? fallbackMs
        let reactions = ((node["reactions"] as? [[String: Any]]) ?? []).compactMap {
            ($0["reaction"] as? String) ?? ($0["emoji"] as? String)
        }

        return IGDirectMessage(
            id: id,
            senderFBID: senderFBID,
            senderUsername: senderDict?["username"] as? String,
            senderAvatarURL: url(senderDict?["profile_pic_url"]),
            text: text,
            timestamp: ms > 0 ? Date(timeIntervalSince1970: ms / 1000) : .now,
            isFromViewer: !viewerFBID.isEmpty && (senderFBID == viewerFBID || senderFBID == viewerID),
            media: media,
            reactions: reactions,
            kind: kind,
            share: share,
            replyTo: replyQuote(node["replied_to_message"] as? [String: Any], viewerFBID: viewerFBID, viewerID: viewerID),
            itemID: string(node["item_id"]) ?? string(node["igd_item_id"]) ?? string(content?["item_id"]),
            audioURL: kind == .voice ? audioURL(in: node) : nil
        )
    }

    private static func messageKind(signature s: String, media: IGMediaItem?, text: String) -> IGDirectMessage.Kind {
        if s.contains("story") { return s.contains("reply") || s.contains("reaction") || s.contains("mention") ? .storyReply : .story }
        if s.contains("clip") || s.contains("reel") { return .reel }
        if s.contains("media_share") || s.contains("mediashare") || s.contains("feed_post") || s.contains("post_share") { return .post }
        if s.contains("voice") || s.contains("audio") { return .voice }
        if s.contains("sticker") || s.contains("animated") || s.contains("gif") { return .sticker }
        if s.contains("like") || s.contains("heart") { return text.isEmpty ? .like : .text }
        if s.contains("link") || s.contains("xma") { return media != nil ? .post : .link }
        if let media { return media.videoURL != nil ? .video : .photo }
        return .text
    }

    private static func typeNames(in value: Any, depth: Int) -> [String] {
        guard depth < 4 else { return [] }
        if let dict = value as? [String: Any] {
            var names = [dict["__typename"], dict["xma_type"], dict["attachment_type"], dict["content_type"]].compactMap { $0 as? String }
            for (key, child) in dict where !skippedAttachmentKeys.contains(key) {
                names += typeNames(in: child, depth: depth + 1)
            }
            return names
        }
        if let array = value as? [Any] { return array.prefix(4).flatMap { typeNames(in: $0, depth: depth + 1) } }
        return []
    }

    /// Owner, caption and link of a shared reel, post or story.
    private static func sharePreview(in node: [String: Any]) -> IGDirectMessage.SharePreview? {
        var preview = IGDirectMessage.SharePreview()
        func first(_ keys: [String], in dict: [String: Any]) -> String? {
            for key in keys { if let text = dict[key] as? String, !text.isEmpty { return text } }
            return nil
        }
        func walk(_ value: Any, depth: Int) {
            guard depth < 9 else { return }
            if let dict = value as? [String: Any] {
                preview.title = preview.title ?? first(["header_title_text", "title_text", "xma_title", "username"], in: dict)
                preview.subtitle = preview.subtitle ?? first(["subtitle_text", "caption_body_text", "xma_subtitle", "caption_text"], in: dict)
                    ?? ((dict["caption"] as? [String: Any])?["text"] as? String)
                if preview.url == nil, let link = first(["target_url", "xma_target_url", "cta_url", "permalink"], in: dict) {
                    preview.url = URL(string: link)
                }
                if preview.avatarURL == nil, let avatar = first(["header_icon_url", "profile_pic_url"], in: dict) {
                    preview.avatarURL = URL(string: avatar)
                }
                for (key, child) in dict where !skippedAttachmentKeys.contains(key) {
                    walk(child, depth: depth + 1)
                }
            } else if let array = value as? [Any] {
                array.forEach { walk($0, depth: depth + 1) }
            }
        }
        walk(node, depth: 0)
        return preview.title == nil && preview.url == nil && preview.subtitle == nil ? nil : preview
    }

    private static func replyQuote(_ dict: [String: Any]?, viewerFBID: String, viewerID: String) -> IGDirectMessage.ReplyQuote? {
        guard let dict else { return nil }
        let content = dict["content"] as? [String: Any]
        let text = (dict["text_body"] as? String) ?? (content?["text_body"] as? String) ?? (dict["igd_snippet"] as? String) ?? ""
        let sender = dict["sender"] as? [String: Any]
        let senderDict = sender?["user_dict"] as? [String: Any]
        let fbid = string(dict["sender_fbid"]) ?? string(senderDict?["interop_messaging_user_fbid"]) ?? string(sender?["id"]) ?? ""
        return IGDirectMessage.ReplyQuote(
            text: text.isEmpty ? "Ek" : text,
            senderUsername: senderDict?["username"] as? String,
            isFromViewer: !fbid.isEmpty && (fbid == viewerFBID || fbid == viewerID)
        )
    }

    private static func audioURL(in node: [String: Any]) -> URL? {
        var found: URL?
        func walk(_ value: Any, depth: Int) {
            guard found == nil, depth < 9 else { return }
            if let dict = value as? [String: Any] {
                for (key, child) in dict {
                    if let text = child as? String, key.lowercased().contains("audio") || key.contains("playable_url") || key == "audio_src",
                       let link = URL(string: text), link.scheme?.hasPrefix("http") == true {
                        found = link
                        return
                    }
                }
                for (key, child) in dict where !skippedAttachmentKeys.contains(key) { walk(child, depth: depth + 1) }
            } else if let array = value as? [Any] {
                array.forEach { walk($0, depth: depth + 1) }
            }
        }
        walk(node, depth: 0)
        return found
    }
}

// MARK: - Schema dump (developer aid)

/// When the app is started with `PRISMGRAM_SCHEMA_DUMP=<folder>`, tapped direct-message responses are
/// written there with every value replaced by its type, so their structure can be studied without
/// recording anyone's messages. Only names of fields and of kinds (`__typename`, `*_type`) are kept.
enum SchemaDump {
    static let folder: URL? = ProcessInfo.processInfo.environment["PRISMGRAM_SCHEMA_DUMP"].map { URL(fileURLWithPath: $0, isDirectory: true) }

    static func write(_ json: [String: Any], name: String) {
        guard let folder else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let redacted = redact(json, key: "")
        guard let data = try? JSONSerialization.data(withJSONObject: redacted, options: [.prettyPrinted, .sortedKeys]) else { return }
        let file = folder.appendingPathComponent("\(name)-\(Int(Date.now.timeIntervalSince1970 * 1000)).json")
        try? data.write(to: file)
    }

    private static func redact(_ value: Any, key: String) -> Any {
        if let dict = value as? [String: Any] {
            return Dictionary(uniqueKeysWithValues: dict.map { ($0.key, redact($0.value, key: $0.key)) })
        }
        if let array = value as? [Any] {
            return array.prefix(4).map { redact($0, key: key) }
        }
        if let text = value as? String {
            let lower = key.lowercased()
            if lower == "__typename" || lower.hasSuffix("_type") || lower == "type" { return text }
            if let link = URL(string: text), let host = link.host { return "<url \(host)>" }
            return "<string>"
        }
        if value is NSNumber { return (value as? Bool) != nil && CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() ? "<bool>" : "<number>" }
        return value is NSNull ? "<null>" : "<other>"
    }
}
