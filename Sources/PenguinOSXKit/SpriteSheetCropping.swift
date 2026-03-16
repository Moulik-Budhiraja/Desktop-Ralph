import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct CroppedSprite: Sendable {
    public let label: String
    public let rowIndex: Int
    public let spriteIndex: Int
    public let bounds: CGRect

    public init(label: String, rowIndex: Int, spriteIndex: Int, bounds: CGRect) {
        self.label = label
        self.rowIndex = rowIndex
        self.spriteIndex = spriteIndex
        self.bounds = bounds
    }
}

public enum SpriteSheetCropError: Error {
    case unableToLoadImage(URL)
    case missingPixelData
    case unableToCreateCrop(CGRect)
    case unableToEncodeImage(URL)
}

public struct SpriteSheetCropper: Sendable {
    public struct Config: Sendable {
        public var whiteThreshold: UInt8
        public var minimumOpaquePixels: Int
        public var minimumWidth: Int
        public var minimumHeight: Int
        public var rowMergeTolerance: CGFloat
        public var rowLabels: [String]

        public init(
            whiteThreshold: UInt8 = 245,
            minimumOpaquePixels: Int = 20_000,
            minimumWidth: Int = 120,
            minimumHeight: Int = 120,
            rowMergeTolerance: CGFloat = 90,
            rowLabels: [String] = ["idle", "walk", "run", "jump_fall", "interact", "hurt_ko"]
        ) {
            self.whiteThreshold = whiteThreshold
            self.minimumOpaquePixels = minimumOpaquePixels
            self.minimumWidth = minimumWidth
            self.minimumHeight = minimumHeight
            self.rowMergeTolerance = rowMergeTolerance
            self.rowLabels = rowLabels
        }
    }

    public struct ExportManifest: Codable, Sendable {
        public let sourceImage: String
        public let spriteCount: Int
        public let sprites: [SpriteRecord]
    }

    public struct SpriteRecord: Codable, Sendable {
        public let label: String
        public let rowIndex: Int
        public let spriteIndex: Int
        public let x: Int
        public let y: Int
        public let width: Int
        public let height: Int
        public let filename: String
    }

    private let config: Config

    public init(config: Config = Config()) {
        self.config = config
    }

    public func exportSprites(from sourceURL: URL, to outputDirectory: URL) throws -> ExportManifest {
        let sourceImage = try loadImage(at: sourceURL)
        let sprites = try detectSprites(in: sourceImage)

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        var records: [SpriteRecord] = []
        for sprite in sprites {
            let cropped = try crop(sprite.bounds, from: sourceImage)
            let filename = "\(sprite.label).png"
            let destinationURL = outputDirectory.appendingPathComponent(filename)
            try savePNG(cropped, to: destinationURL)

            records.append(
                SpriteRecord(
                    label: sprite.label,
                    rowIndex: sprite.rowIndex,
                    spriteIndex: sprite.spriteIndex,
                    x: Int(sprite.bounds.origin.x.rounded()),
                    y: Int(sprite.bounds.origin.y.rounded()),
                    width: Int(sprite.bounds.width.rounded()),
                    height: Int(sprite.bounds.height.rounded()),
                    filename: filename
                )
            )
        }

        let manifest = ExportManifest(
            sourceImage: sourceURL.lastPathComponent,
            spriteCount: records.count,
            sprites: records
        )

        let manifestURL = outputDirectory.appendingPathComponent("sprites.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL)

        return manifest
    }

    public func detectSprites(in image: CGImage) throws -> [CroppedSprite] {
        let width = image.width
        let height = image.height

        guard let dataProvider = image.dataProvider, let pixelData = dataProvider.data else {
            throw SpriteSheetCropError.missingPixelData
        }

        let bytes = CFDataGetBytePtr(pixelData)!
        let bytesPerRow = image.bytesPerRow
        let bytesPerPixel = image.bitsPerPixel / 8

        var visited = Array(repeating: false, count: width * height)
        var bounds: [CGRect] = []

        func pixelOffset(x: Int, y: Int) -> Int {
            (y * bytesPerRow) + (x * bytesPerPixel)
        }

        func isSpritePixel(x: Int, y: Int) -> Bool {
            let offset = pixelOffset(x: x, y: y)
            let alpha = bytes[offset + 3]
            if alpha == 0 {
                return false
            }

            let red = bytes[offset]
            let green = bytes[offset + 1]
            let blue = bytes[offset + 2]
            return !(red > config.whiteThreshold && green > config.whiteThreshold && blue > config.whiteThreshold)
        }

        let directions = [(-1, 0), (1, 0), (0, -1), (0, 1)]

        for y in 0..<height {
            for x in 0..<width {
                let flatIndex = (y * width) + x
                if visited[flatIndex] || !isSpritePixel(x: x, y: y) {
                    continue
                }

                var queue = [(x: Int, y: Int)]()
                queue.reserveCapacity(8_192)
                queue.append((x, y))
                visited[flatIndex] = true

                var cursor = 0
                var minX = x
                var maxX = x
                var minY = y
                var maxY = y

                while cursor < queue.count {
                    let point = queue[cursor]
                    cursor += 1

                    minX = min(minX, point.x)
                    maxX = max(maxX, point.x)
                    minY = min(minY, point.y)
                    maxY = max(maxY, point.y)

                    for direction in directions {
                        let nextX = point.x + direction.0
                        let nextY = point.y + direction.1
                        guard nextX >= 0, nextX < width, nextY >= 0, nextY < height else {
                            continue
                        }

                        let nextFlatIndex = (nextY * width) + nextX
                        if visited[nextFlatIndex] || !isSpritePixel(x: nextX, y: nextY) {
                            continue
                        }

                        visited[nextFlatIndex] = true
                        queue.append((nextX, nextY))
                    }
                }

                let spriteWidth = maxX - minX + 1
                let spriteHeight = maxY - minY + 1
                if queue.count >= config.minimumOpaquePixels,
                   spriteWidth >= config.minimumWidth,
                   spriteHeight >= config.minimumHeight {
                    bounds.append(
                        CGRect(
                            x: minX,
                            y: minY,
                            width: spriteWidth,
                            height: spriteHeight
                        )
                    )
                }
            }
        }

        return labelSprites(bounds.sorted { lhs, rhs in
            if abs(lhs.midY - rhs.midY) > config.rowMergeTolerance {
                return lhs.minY < rhs.minY
            }
            return lhs.minX < rhs.minX
        })
    }

    public func labelSprites(_ bounds: [CGRect]) -> [CroppedSprite] {
        let rows = groupRows(bounds)

        return rows.enumerated().flatMap { rowIndex, rowBounds in
            let rowLabel = config.rowLabels.indices.contains(rowIndex) ? config.rowLabels[rowIndex] : "row_\(rowIndex + 1)"
            let sortedBounds = rowBounds.sorted { $0.minX < $1.minX }

            return sortedBounds.enumerated().map { spriteIndex, bounds in
                CroppedSprite(
                    label: "\(rowLabel)_\(String(format: "%02d", spriteIndex + 1))",
                    rowIndex: rowIndex,
                    spriteIndex: spriteIndex,
                    bounds: bounds
                )
            }
        }
    }

    private func groupRows(_ bounds: [CGRect]) -> [[CGRect]] {
        var rows: [[CGRect]] = []

        for rect in bounds.sorted(by: { $0.minY < $1.minY }) {
            if let lastIndex = rows.indices.last {
                let lastMidY = rows[lastIndex].map(\.midY).reduce(0, +) / CGFloat(rows[lastIndex].count)
                if abs(rect.midY - lastMidY) <= config.rowMergeTolerance {
                    rows[lastIndex].append(rect)
                    continue
                }
            }
            rows.append([rect])
        }

        return rows
    }

    private func loadImage(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw SpriteSheetCropError.unableToLoadImage(url)
        }

        return image
    }

    private func crop(_ rect: CGRect, from image: CGImage) throws -> CGImage {
        let cropRect = CGRect(
            x: rect.origin.x,
            y: CGFloat(image.height) - rect.maxY,
            width: rect.width,
            height: rect.height
        ).integral

        guard let cropped = image.cropping(to: cropRect) else {
            throw SpriteSheetCropError.unableToCreateCrop(rect)
        }

        return cropped
    }

    private func savePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw SpriteSheetCropError.unableToEncodeImage(url)
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw SpriteSheetCropError.unableToEncodeImage(url)
        }
    }
}
