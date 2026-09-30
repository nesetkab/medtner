import AppKit
import ImageIO
import SwiftUI

actor ArtworkStore {
    static let shared = ArtworkStore()

    nonisolated(unsafe) private let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 60
        cache.totalCostLimit = 30 * 1024 * 1024
        return cache
    }()
    private var inflight: [URL: Task<NSImage?, Never>] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 0, diskCapacity: 64 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    nonisolated static func decode(_ data: Data, maxPixels: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    nonisolated func cached(_ url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func image(_ url: URL) async -> NSImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        if let task = inflight[url] { return await task.value }
        let task = Task<NSImage?, Never> {
            guard let (data, _) = try? await session.data(from: url) else { return nil }
            return Self.decode(data, maxPixels: 640)
        }
        inflight[url] = task
        let image = await task.value
        inflight[url] = nil
        if let image {
            let cost = Int(image.size.width * image.size.height * 4)
            cache.setObject(image, forKey: url as NSURL, cost: cost)
        }
        return image
    }
}

enum Palette {
    static let background = Color(red: 0.067, green: 0.067, blue: 0.067)
    static let tile = Color(white: 0.85)
    static let muted = Color(white: 0.55)
    static let defaultAccent = NSColor(red: 0.84, green: 0.72, blue: 1.0, alpha: 1)
    static let placeholder: NSImage? = Bundle.main.url(forResource: "Cover", withExtension: "svg").flatMap(NSImage.init(contentsOf:))

    static func accent(from image: NSImage) -> NSColor {
        palette(from: image).first ?? defaultAccent
    }

    static func palette(from image: NSImage) -> [NSColor] {
        let size = 24
        guard
            let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let context = CGContext(
                data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return [defaultAccent] }
        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return [defaultAccent] }

        var buckets: [Int: (score: Double, r: Double, g: Double, b: Double, n: Double)] = [:]
        for i in 0..<(size * size) {
            let r = Double(data[i * 4]) / 255, g = Double(data[i * 4 + 1]) / 255, b = Double(data[i * 4 + 2]) / 255
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0
            NSColor(red: r, green: g, blue: b, alpha: 1).getHue(&h, saturation: &s, brightness: &v, alpha: nil)
            guard s > 0.2, v > 0.25 else { continue }
            let key = Int(h * 12) % 12
            var bucket = buckets[key] ?? (0, 0, 0, 0, 0)
            bucket.score += Double(s * s) * Double(v)
            bucket.r += r; bucket.g += g; bucket.b += b; bucket.n += 1
            buckets[key] = bucket
        }
        let ranked = buckets.values.filter { $0.n > 2 }.sorted { $0.score > $1.score }
        let colors = ranked.prefix(3).map { bucket -> NSColor in
            let base = NSColor(red: bucket.r / bucket.n, green: bucket.g / bucket.n, blue: bucket.b / bucket.n, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0
            base.getHue(&h, saturation: &s, brightness: &v, alpha: nil)
            return NSColor(hue: h, saturation: min(max(s, 0.45), 0.85), brightness: max(v, 0.88), alpha: 1)
        }
        return colors.isEmpty ? [defaultAccent] : colors
    }
}

struct Art: View {
    let url: URL?
    var radius: CGFloat = 16
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Palette.tile)
            if url == nil, let placeholder = Palette.placeholder {
                Image(nsImage: placeholder)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            }
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            if let hit = ArtworkStore.shared.cached(url) {
                image = hit
                return
            }
            let loaded = await ArtworkStore.shared.image(url)
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
        }
    }
}
