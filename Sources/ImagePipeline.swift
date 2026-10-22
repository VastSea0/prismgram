import SwiftUI
import AppKit
import ImageIO

/// Loads, downsamples and caches remote images.
///
/// `AsyncImage` keeps nothing between appearances, so every cell that scrolled back into a lazy
/// stack downloaded and decoded its image again and flashed its placeholder. This pipeline keeps
/// decoded bitmaps in memory, raw responses on disk, and joins concurrent requests for the same URL.
@MainActor
final class ImagePipeline {
    static let shared = ImagePipeline()

    private let memory = NSCache<NSString, NSImage>()
    private var inflight: [String: Task<NSImage?, Never>] = [:]
    private let session: URLSession

    private init() {
        memory.totalCostLimit = 256 * 1024 * 1024

        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Prismgram/Images", isDirectory: true)
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 512 * 1024 * 1024, directory: directory)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.httpMaximumConnectionsPerHost = 8
        session = URLSession(configuration: configuration)
    }

    private static func key(_ url: URL, _ maxPixelSize: CGFloat) -> String {
        "\(Int(maxPixelSize))|\(url.absoluteString)"
    }

    func cached(_ url: URL?, maxPixelSize: CGFloat) -> NSImage? {
        guard let url else { return nil }
        return memory.object(forKey: Self.key(url, maxPixelSize) as NSString)
    }

    func image(for url: URL, maxPixelSize: CGFloat) async -> NSImage? {
        let key = Self.key(url, maxPixelSize)
        if let hit = memory.object(forKey: key as NSString) { return hit }
        if let running = inflight[key] { return await running.value }

        let session = session
        let task = Task<NSImage?, Never> {
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else { return nil }
            let decoded = await Task.detached(priority: .userInitiated) {
                Self.decode(data, maxPixelSize: maxPixelSize)
            }.value
            return decoded.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        }
        inflight[key] = task
        let result = await task.value
        inflight[key] = nil
        if let result {
            let cost = Int(result.size.width * result.size.height * 4)
            memory.setObject(result, forKey: key as NSString, cost: cost)
        }
        return result
    }

    /// Warms the cache for images that are about to be shown (the next story slide, the next carousel page).
    func prefetch(_ urls: [URL?], maxPixelSize: CGFloat) {
        for case let url? in urls where cached(url, maxPixelSize: maxPixelSize) == nil {
            Task { _ = await image(for: url, maxPixelSize: maxPixelSize) }
        }
    }

    nonisolated private static func decode(_ data: Data, maxPixelSize: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, maxPixelSize)
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// A remote image drawn from `ImagePipeline`. Shows the cached bitmap on the very first frame when it has one.
struct CachedImage<Placeholder: View>: View {
    let url: URL?
    var maxPixelSize: CGFloat = 1080
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: (_ failed: Bool) -> Placeholder

    @State private var image: NSImage?
    @State private var failed = false

    init(url: URL?, maxPixelSize: CGFloat = 1080, contentMode: ContentMode = .fill, @ViewBuilder placeholder: @escaping (_ failed: Bool) -> Placeholder) {
        self.url = url
        self.maxPixelSize = maxPixelSize
        self.contentMode = contentMode
        self.placeholder = placeholder
        _image = State(initialValue: ImagePipeline.shared.cached(url, maxPixelSize: maxPixelSize))
    }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder(failed)
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                failed = true
                return
            }
            if let hit = ImagePipeline.shared.cached(url, maxPixelSize: maxPixelSize) {
                image = hit
                return
            }
            failed = false
            let loaded = await ImagePipeline.shared.image(for: url, maxPixelSize: maxPixelSize)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                image = loaded
                failed = loaded == nil
            }
        }
    }
}
