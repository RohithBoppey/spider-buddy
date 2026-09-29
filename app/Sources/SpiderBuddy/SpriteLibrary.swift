import AppKit
import ImageIO

/// One sprite frame, plus its alpha channel for pixel-accurate hit testing.
final class Sprite {
    let image: CGImage
    let width: Int
    let height: Int
    private let alpha: [UInt8]

    init?(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = image.width, height = image.height
        self.image = image
        self.width = width
        self.height = height

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        alpha = stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
    }

    /// x, y in sprite pixels, y measured from the top.
    func isOpaque(x: Int, y: Int) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height else { return false }
        return alpha[y * width + x] > 0
    }
}

/// Loads the pose folders (top-hang, pickup, ...) as sorted frame lists.
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
            let files = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "png" && !$0.lastPathComponent.hasPrefix("_") }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            animations[folder.lastPathComponent] = files.compactMap(Sprite.init(url:))
        }
    }

    func frames(_ name: String) -> [Sprite] {
        animations[name] ?? []
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
