import AppKit
import ImageIO

/// One sprite frame, plus its alpha channel for pixel-accurate hit testing.
final class Sprite {
    let name: String
    let image: CGImage
    let width: Int
    let height: Int
    /// Point that stays fixed while an animation plays (sprite pixels from the top-left),
    /// from the folder's anchors.json; nil when the folder has none.
    let anchor: CGPoint?
    private let alpha: [UInt8]

    private init(name: String, image: CGImage, anchor: CGPoint?, alpha: [UInt8]) {
        self.name = name
        self.image = image
        width = image.width
        height = image.height
        self.anchor = anchor
        self.alpha = alpha
    }

    convenience init?(url: URL, anchor: CGPoint?) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let rgba = Self.rgba(of: image, mirrored: false) else { return nil }
        let alpha = stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
        self.init(name: url.deletingPathExtension().lastPathComponent, image: image, anchor: anchor, alpha: alpha)
    }

    /// Horizontally flipped copy (all frames face one way; the other way is mirrored at load).
    func mirrored() -> Sprite {
        guard let rgba = Self.rgba(of: image, mirrored: true),
              let provider = CGDataProvider(data: Data(rgba) as CFData),
              let flipped = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return self }
        let alpha = stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
        let flippedAnchor = anchor.map { CGPoint(x: CGFloat(width) - $0.x, y: $0.y) }
        return Sprite(name: name, image: flipped, anchor: flippedAnchor, alpha: alpha)
    }

    /// x, y in sprite pixels, y measured from the top.
    func isOpaque(x: Int, y: Int) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height else { return false }
        return alpha[y * width + x] > 0
    }

    /// Premultiplied RGBA bytes, rows top to bottom.
    private static func rgba(of image: CGImage, mirrored: Bool) -> [UInt8]? {
        let width = image.width, height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            if mirrored {
                ctx.translateBy(x: CGFloat(width), y: 0)
                ctx.scaleBy(x: -1, y: 1)
            }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? rgba : nil
    }
}

/// Loads the pose folders (top-hang, pickup, ...) as frame lists sorted by file name.
final class SpriteLibrary {
    private var animations: [String: [Sprite]] = [:]

    init() {
        guard let root = Self.spritesRoot() else {
            NSLog("SpiderBuddy: no sprite folder found")
            return
        }
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for folder in folders where folder.hasDirectoryPath {
            let anchors = Self.anchors(in: folder)
            let files = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "png" && !$0.lastPathComponent.hasPrefix("_") }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            animations[folder.lastPathComponent] = files.compactMap {
                Sprite(url: $0, anchor: anchors[$0.deletingPathExtension().lastPathComponent])
            }
        }
    }

    func frames(_ name: String) -> [Sprite] {
        animations[name] ?? []
    }

    /// anchors.json: {"frame name": [x, y], ...}
    private static func anchors(in folder: URL) -> [String: CGPoint] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("anchors.json")),
              let raw = try? JSONDecoder().decode([String: [Double]].self, from: data) else { return [:] }
        return raw.compactMapValues { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
    }

    /// Inside the .app: Contents/Resources/Sprites. From `swift run` in app/: ../frames-custom.
    private static func spritesRoot() -> URL? {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let res = Bundle.main.resourceURL {
            candidates.append(res.appendingPathComponent("Sprites"))
        }
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        candidates.append(cwd.appendingPathComponent("../frames-custom"))
        candidates.append(cwd.appendingPathComponent("frames-custom"))
        return candidates.first { fm.fileExists(atPath: $0.path) }
    }
}
