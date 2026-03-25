import CoreGraphics
import CoreImage
import CoreMedia

/// Stateful temporal grid effect.
/// Each frame shifts cells through an upward-flowing grid chain:
/// - bottom-left receives current-frame content scaled to one cell
/// - every other cell receives prior output from the prior cell in flow order,
///   sampled `frameOffset` frames back
/// Flow order is bottom->top per column, then left->right across columns.
public final class TemporalGridShift: StatefulFilter {
    public var filterAnimators: [FilterAnimator]

    public var columns: Int
    public var rows: Int
    public var frameOffset: Int

    private var outputHistory: [CIImage] = []
    private let context = CIContext(options: [CIContextOption.cacheIntermediates: false])

    public init(
        columns: Int = 3,
        rows: Int = 3,
        frameOffset: Int = 1,
        filterAnimators: [FilterAnimator] = []
    ) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
        self.frameOffset = max(1, frameOffset)
        self.filterAnimators = filterAnimators
    }

    public func resetState() {
        outputHistory.removeAll(keepingCapacity: false)
    }

    public func updateFilterValue(filterProperty: FilterProperty, value: Any) {
        switch filterProperty {
        case .intensity:
            if let value = value as? Double {
                let size = max(1, Int(value.rounded()))
                columns = size
                rows = size
            }
        default:
            break
        }
    }

    public func filterContent(
        image: CIImage,
        sourceTime: CMTime?,
        sceneTime: CMTime?,
        compositionTime: CMTime?
    ) -> CIImage? {
        let extent = image.extent
        let cols = max(1, columns)
        let rowCount = max(1, rows)
        let spacing = max(1, frameOffset)
        let flowRects = orderedFlowRects(in: extent, columns: cols, rows: rowCount)
        let historyIndex = spacing - 1
        let historySource = outputHistory.indices.contains(historyIndex) ? outputHistory[historyIndex] : outputHistory.last

        guard let previous = historySource else {
            let seeded = seededGrid(from: image, extent: extent, flowRects: flowRects)
            let snapshot = flattened(seeded, to: extent)
            pushHistory(snapshot)
            return snapshot
        }

        var output: CIImage?

        for index in 0..<flowRects.count {
            let destRect = flowRects[index]

            let tile: CIImage

            if index == 0 {
                // Entry point for newest content uses full-frame scaled image.
                tile = scaledImage(image, from: extent, to: destRect)
            } else {
                // Pull from prior cell in the temporal flow.
                let sourceRect = flowRects[index - 1]
                tile = previous
                    .cropped(to: sourceRect)
                    .transformed(
                        by: CGAffineTransform(
                            translationX: destRect.minX - sourceRect.minX,
                            y: destRect.minY - sourceRect.minY
                        )
                    )
                    .cropped(to: destRect)
            }

            if let existing = output {
                output = tile.composited(over: existing)
            } else {
                output = tile
            }
        }

        let composed = (output ?? image).cropped(to: extent)
        let snapshot = flattened(composed, to: extent)
        pushHistory(snapshot)
        return snapshot
    }

    private func pushHistory(_ image: CIImage) {
        outputHistory.insert(image, at: 0)
        let keep = max(2, frameOffset + 1)
        if outputHistory.count > keep {
            outputHistory.removeSubrange(keep..<outputHistory.count)
        }
    }

    private func seededGrid(from image: CIImage, extent: CGRect, flowRects: [CGRect]) -> CIImage {
        var seeded: CIImage?
        for rect in flowRects {
            let tile = scaledImage(image, from: extent, to: rect)
            if let existing = seeded {
                seeded = tile.composited(over: existing)
            } else {
                seeded = tile
            }
        }
        return (seeded ?? image).cropped(to: extent)
    }

    private func scaledImage(_ image: CIImage, from sourceExtent: CGRect, to destRect: CGRect) -> CIImage {
        let translatedToOrigin = image.transformed(
            by: CGAffineTransform(translationX: -sourceExtent.minX, y: -sourceExtent.minY)
        )
        let scaleX = destRect.width / sourceExtent.width
        let scaleY = destRect.height / sourceExtent.height
        let scaled = translatedToOrigin.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        return scaled
            .transformed(by: CGAffineTransform(translationX: destRect.minX, y: destRect.minY))
            .cropped(to: destRect)
    }

    private func flattened(_ image: CIImage, to extent: CGRect) -> CIImage {
        guard let cgImage = context.createCGImage(image, from: extent) else {
            return image.cropped(to: extent)
        }
        return CIImage(cgImage: cgImage).cropped(to: extent)
    }

    private func orderedFlowRects(in extent: CGRect, columns: Int, rows: Int) -> [CGRect] {
        let cellWidth = extent.width / CGFloat(columns)
        let cellHeight = extent.height / CGFloat(rows)

        var rects: [CGRect] = []
        rects.reserveCapacity(columns * rows)

        // Bottom->top in each column (upward), then left->right across columns.
        for col in 0..<columns {
            for row in 0..<rows {
                rects.append(
                    CGRect(
                        x: extent.minX + CGFloat(col) * cellWidth,
                        y: extent.minY + CGFloat(row) * cellHeight,
                        width: cellWidth,
                        height: cellHeight
                    )
                )
            }
        }

        return rects
    }
}
