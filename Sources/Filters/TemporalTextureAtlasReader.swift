import CoreGraphics
import CoreImage
import Metal
import Foundation

/// Converts frames stored in a temporal atlas texture into CIImage outputs.
/// `indices` are relative to `frameZeroIndex` (`0` = most recent frame, `1` = previous frame).
public final class TemporalTextureAtlasReader {
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    public init() {}

    public func images(
        from snapshot: TemporalTextureAtlasSnapshot,
        indices: [Int],
        outputSize: CGSize? = nil
    ) -> [CIImage] {
        images(
            texture: snapshot.texture,
            textureSize: snapshot.textureSize,
            cellSize: snapshot.cellSize,
            columns: snapshot.columns,
            rows: snapshot.rows,
            frameCount: snapshot.frameCount,
            frameZeroIndex: snapshot.frameZeroIndex,
            indices: indices,
            outputSize: outputSize
        )
    }

    public func images(
        texture: MTLTexture,
        textureSize: CGSize,
        cellSize: CGSize,
        columns: Int,
        rows: Int,
        frameCount: Int,
        frameZeroIndex: Int,
        indices: [Int],
        outputSize: CGSize? = nil
    ) -> [CIImage] {
        guard
            columns > 0,
            rows > 0,
            frameCount > 0
        else {
            return []
        }

        guard texture.width == Int(textureSize.width.rounded()), texture.height == Int(textureSize.height.rounded()) else {
            return images(
                texture: texture,
                textureSize: CGSize(width: texture.width, height: texture.height),
                cellSize: cellSize,
                columns: columns,
                rows: rows,
                frameCount: frameCount,
                frameZeroIndex: frameZeroIndex,
                indices: indices,
                outputSize: outputSize
            )
        }

        guard let atlasImage = CIImage(mtlTexture: texture, options: [CIImageOption.colorSpace: colorSpace]) else {
            return []
        }

        let clampedFrameCount = min(max(0, frameCount), max(1, columns * rows))
        guard clampedFrameCount > 0 else { return [] }

        let requested = indices.isEmpty ? [0] : indices
        var output: [CIImage] = []
        output.reserveCapacity(requested.count)

        for rawIndex in requested {
            let relative = min(max(0, rawIndex), clampedFrameCount - 1)
            let absolute = positiveModulo(frameZeroIndex - relative, columns * rows)
            let sourceRect = rectForAbsoluteIndex(
                absolute,
                columns: columns,
                cellSize: cellSize
            )
            if sourceRect.width <= 0 || sourceRect.height <= 0 {
                continue
            }

            let cropped = atlasImage.cropped(to: sourceRect)
            let originRect = CGRect(origin: .zero, size: sourceRect.size)
            let normalized = cropped
                .transformed(by: CGAffineTransform(translationX: -sourceRect.minX, y: -sourceRect.minY))
                .cropped(to: originRect)

            if let outputSize, outputSize.width > 0, outputSize.height > 0 {
                let destination = CGRect(origin: .zero, size: outputSize)
                output.append(
                    scaledImage(normalized, from: originRect, to: destination)
                        .cropped(to: destination)
                )
            } else {
                output.append(normalized)
            }
        }

        return output
    }

    private func rectForAbsoluteIndex(_ index: Int, columns: Int, cellSize: CGSize) -> CGRect {
        let col = index % columns
        let row = index / columns
        return CGRect(
            x: CGFloat(col) * cellSize.width,
            y: CGFloat(row) * cellSize.height,
            width: cellSize.width,
            height: cellSize.height
        )
    }

    private func scaledImage(_ image: CIImage, from sourceRect: CGRect, to destRect: CGRect) -> CIImage {
        let movedToOrigin = image.transformed(
            by: CGAffineTransform(translationX: -sourceRect.minX, y: -sourceRect.minY)
        )
        let sx = destRect.width / sourceRect.width
        let sy = destRect.height / sourceRect.height
        return movedToOrigin
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .transformed(by: CGAffineTransform(translationX: destRect.minX, y: destRect.minY))
            .cropped(to: destRect)
    }

    private func positiveModulo(_ value: Int, _ modulus: Int) -> Int {
        guard modulus > 0 else { return 0 }
        let remainder = value % modulus
        return remainder >= 0 ? remainder : remainder + modulus
    }
}
