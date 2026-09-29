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
    /// Centre of the eyes (sprite pixels from the top-left): where speech bubbles point.
    let face: CGPoint?
    private let alpha: [UInt8]

    private init(name: String, image: CGImage, anchor: CGPoint?, face: CGPoint?, alpha: [UInt8]) {
        self.name = name
        self.image = image
        width = image.width
        height = image.height
        self.anchor = anchor
        self.face = face
        self.alpha = alpha
    }

    convenience init?(url: URL, anchor: CGPoint?) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let rgba = Self.rgba(of: image, flipX: false, flipY: false) else { return nil }
        let alpha = stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
        self.init(name: url.deletingPathExtension().lastPathComponent, image: image, anchor: anchor,
                  face: Self.eyeCentre(rgba, width: image.width, height: image.height), alpha: alpha)
    }

    /// Horizontally flipped copy (all frames face one way; the other way is mirrored at load).
    func mirrored() -> Sprite {
        transformed(flipX: true, flipY: false)
    }

    /// Vertically flipped copy (head down, for climbing down a wall head-first).
    func flippedVertically() -> Sprite {
        transformed(flipX: false, flipY: true)
    }

    private func transformed(flipX: Bool, flipY: Bool) -> Sprite {
        guard let rgba = Self.rgba(of: image, flipX: flipX, flipY: flipY),
              let provider = CGDataProvider(data: Data(rgba) as CFData),
              let flipped = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return self }
        let alpha = stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
        func flip(_ p: CGPoint) -> CGPoint {
            CGPoint(x: flipX ? CGFloat(width) - p.x : p.x, y: flipY ? CGFloat(height) - p.y : p.y)
        }
        return Sprite(name: name, image: flipped, anchor: anchor.map(flip), face: face.map(flip), alpha: alpha)
    }

    /// x, y in sprite pixels, y measured from the top.
    func isOpaque(x: Int, y: Int) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height else { return false }
        return alpha[y * width + x] > 0
    }

    /// Centroid of the eye pixels: eye white #D6DED6 plus shade #A5A5A5, or #DEDEDE plus shade for
    /// frames drawn with that white (018, 087). #DEDEDE alone is not used where #D6DED6 exists
    /// because the hanging frames' web stub is #DEDEDE.
    private static func eyeCentre(_ rgba: [UInt8], width: Int, height: Int) -> CGPoint? {
        func pixels(_ whites: [(UInt8, UInt8, UInt8)]) -> [CGPoint] {
            let colours = whites + [(0xA5, 0xA5, 0xA5)]
            var points: [CGPoint] = []
            for y in 0..<height {
                for x in 0..<width {
                    let i = (y * width + x) * 4
                    guard rgba[i + 3] == 255 else { continue }
                    if colours.contains(where: { $0 == (rgba[i], rgba[i + 1], rgba[i + 2]) }) {
                        points.append(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5))
                    }
                }
            }
            return points
        }
        var eye = pixels([(0xD6, 0xDE, 0xD6)])
        if eye.count < 3 { eye = pixels([(0xD6, 0xDE, 0xD6), (0xDE, 0xDE, 0xDE)]) }
        guard !eye.isEmpty else { return nil }
        let n = CGFloat(eye.count)
        return CGPoint(x: eye.map(\.x).reduce(0, +) / n, y: eye.map(\.y).reduce(0, +) / n)
    }

    /// Premultiplied RGBA bytes, rows top to bottom.
    private static func rgba(of image: CGImage, flipX: Bool, flipY: Bool) -> [UInt8]? {
        let width = image.width, height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.translateBy(x: flipX ? CGFloat(width) : 0, y: flipY ? CGFloat(height) : 0)
            ctx.scaleBy(x: flipX ? -1 : 1, y: flipY ? -1 : 1)
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
