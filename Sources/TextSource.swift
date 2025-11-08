//
//  TextSource.swift
//  VideoProcessingTwo
//
//  Created by Jake Gundersen on 7/14/25.
//

import Foundation
import CoreImage
import CoreText
import CoreGraphics
import CoreMedia
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

public class TextSource: Source {
    public struct TextStyle {
        public var font: String
        public var fontSize: CGFloat
        public var color: CGColor
        public var alignment: NSTextAlignment
        public var backgroundColor: CGColor?
        public var strokeColor: CGColor?
        public var strokeWidth: CGFloat
        
        public init(font: String = "Helvetica", fontSize: CGFloat = 24, color: CGColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1), alignment: NSTextAlignment = .center, backgroundColor: CGColor? = nil, strokeColor: CGColor? = nil, strokeWidth: CGFloat = 0) {
            self.font = font
            self.fontSize = fontSize
            self.color = color
            self.alignment = alignment
            self.backgroundColor = backgroundColor
            self.strokeColor = strokeColor
            self.strokeWidth = strokeWidth
        }
    }
    
    public var words: [String]
    public var textStyle: TextStyle
    public var canvasSize: CGSize
    public var wordDuration: Double
    public var animationType: TextAnimationType
    public var maxCharacters: Int
    
    public init(words: [String], textStyle: TextStyle = TextStyle(), canvasSize: CGSize, wordDuration: Double = 1.0, animationType: TextAnimationType = .swap, maxCharacters: Int = 20) {
        self.words = words
        self.textStyle = textStyle
        self.canvasSize = canvasSize
        self.wordDuration = wordDuration
        self.animationType = animationType
        self.maxCharacters = maxCharacters
    }
    
    public func getFrameAtTime(cmTime: CMTime, framesByTrackID: [CMPersistentTrackID: CVPixelBuffer]?) -> Frame? {
        let timeInSeconds = cmTime.seconds
        
        // Create text chunks based on character limit and word boundaries
        let textChunks = createTextChunks()
        
        if textChunks.isEmpty {
            return nil
        }
        
        let currentChunkIndex = Int(timeInSeconds / wordDuration) % textChunks.count
        let timeInChunk = timeInSeconds.truncatingRemainder(dividingBy: wordDuration)
        let progressInChunk = timeInChunk / wordDuration
        
        let currentText = textChunks[currentChunkIndex]
        let nextText = textChunks[(currentChunkIndex + 1) % textChunks.count]
        
        if let textImage = animationType.renderText(
            currentWord: currentText,
            nextWord: nextText,
            progress: progressInChunk,
            style: textStyle,
            canvasSize: canvasSize
        ) {
            let context = CIContext()
            if let cgImage = context.createCGImage(textImage, from: textImage.extent) {
                return LowImageFrame(cgImage: cgImage, time: cmTime)
            }
        }
        
        return nil
    }
    
    private func createTextChunks() -> [String] {
        var chunks: [String] = []
        var currentChunk = ""
        
        for word in words {
            let testChunk = currentChunk.isEmpty ? word : "\(currentChunk) \(word)"
            
            // Check if adding this word would exceed the character limit
            if testChunk.count <= maxCharacters {
                currentChunk = testChunk
            } else {
                // If current chunk is not empty, save it and start a new one
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk)
                    currentChunk = word
                } else {
                    // If a single word exceeds the limit, truncate it
                    currentChunk = String(word.prefix(maxCharacters))
                }
            }
        }
        
        // Add the final chunk if it's not empty
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
        
        return chunks
    }
}

public enum TextAnimationType {
    case swap
    case fadeInOut
    case slideLeft
    case slideRight
    case slideUp
    case slideDown
    case rotateIn
    case scaleIn
    
    func renderText(currentWord: String, nextWord: String, progress: Double, style: TextSource.TextStyle, canvasSize: CGSize) -> CIImage? {
        switch self {
        case .swap:
            return renderSwapAnimation(currentWord: currentWord, nextWord: nextWord, progress: progress, style: style, canvasSize: canvasSize)
        case .fadeInOut:
            return renderFadeAnimation(currentWord: currentWord, nextWord: nextWord, progress: progress, style: style, canvasSize: canvasSize)
        case .slideLeft:
            return renderSlideAnimation(currentWord: currentWord, nextWord: nextWord, progress: progress, style: style, canvasSize: canvasSize, direction: .left)
        case .slideRight:
            return renderSlideAnimation(currentWord: currentWord, nextWord: nextWord, progress: progress, style: style, canvasSize: canvasSize, direction: .right)
        case .slideUp:
            return renderSlideAnimation(currentWord: currentWord, nextWord: nextWord, progress: progress, style: style, canvasSize: canvasSize, direction: .up)
        case .slideDown:
            return renderSlideAnimation(currentWord: currentWord, nextWord: nextWord, progress: progress, style: style, canvasSize: canvasSize, direction: .down)
        case .rotateIn:
            return renderRotateAnimation(currentWord: currentWord, nextWord: nextWord, progress: progress, style: style, canvasSize: canvasSize)
        case .scaleIn:
            return renderScaleAnimation(currentWord: currentWord, nextWord: nextWord, progress: progress, style: style, canvasSize: canvasSize)
        }
    }
    
    private func renderSwapAnimation(currentWord: String, nextWord: String, progress: Double, style: TextSource.TextStyle, canvasSize: CGSize) -> CIImage? {
        let word = progress < 0.5 ? currentWord : nextWord
        return createTextImage(text: word, style: style, canvasSize: canvasSize)
    }
    
    private func renderFadeAnimation(currentWord: String, nextWord: String, progress: Double, style: TextSource.TextStyle, canvasSize: CGSize) -> CIImage? {
        if progress < 0.5 {
            let alpha = 1.0 - (progress * 2)
            var fadeStyle = style
            fadeStyle.color = fadeStyle.color.copy(alpha: alpha)!
            return createTextImage(text: currentWord, style: fadeStyle, canvasSize: canvasSize)
        } else {
            let alpha = (progress - 0.5) * 2
            var fadeStyle = style
            fadeStyle.color = fadeStyle.color.copy(alpha: alpha)!
            return createTextImage(text: nextWord, style: fadeStyle, canvasSize: canvasSize)
        }
    }
    
    private enum SlideDirection {
        case left, right, up, down
    }
    
    private func renderSlideAnimation(currentWord: String, nextWord: String, progress: Double, style: TextSource.TextStyle, canvasSize: CGSize, direction: SlideDirection) -> CIImage? {
        let currentOffset: CGPoint
        let nextOffset: CGPoint
        
        switch direction {
        case .left:
            currentOffset = CGPoint(x: -canvasSize.width * progress, y: 0)
            nextOffset = CGPoint(x: canvasSize.width * (1 - progress), y: 0)
        case .right:
            currentOffset = CGPoint(x: canvasSize.width * progress, y: 0)
            nextOffset = CGPoint(x: -canvasSize.width * (1 - progress), y: 0)
        case .up:
            currentOffset = CGPoint(x: 0, y: canvasSize.height * progress)
            nextOffset = CGPoint(x: 0, y: -canvasSize.height * (1 - progress))
        case .down:
            currentOffset = CGPoint(x: 0, y: -canvasSize.height * progress)
            nextOffset = CGPoint(x: 0, y: canvasSize.height * (1 - progress))
        }
        
        let currentImage = createTextImage(text: currentWord, style: style, canvasSize: canvasSize, offset: currentOffset)
        let nextImage = createTextImage(text: nextWord, style: style, canvasSize: canvasSize, offset: nextOffset)
        
        if let current = currentImage, let next = nextImage {
            return next.composited(over: current)
        }
        return currentImage ?? nextImage
    }
    
    private func renderRotateAnimation(currentWord: String, nextWord: String, progress: Double, style: TextSource.TextStyle, canvasSize: CGSize) -> CIImage? {
        if progress < 0.5 {
            let rotationAngle = progress * 2 * .pi
            let image = createTextImage(text: currentWord, style: style, canvasSize: canvasSize)
            return image?.transformed(by: CGAffineTransform(rotationAngle: rotationAngle))
        } else {
            let rotationAngle = (progress - 0.5) * 2 * .pi
            let image = createTextImage(text: nextWord, style: style, canvasSize: canvasSize)
            return image?.transformed(by: CGAffineTransform(rotationAngle: rotationAngle))
        }
    }
    
    private func renderScaleAnimation(currentWord: String, nextWord: String, progress: Double, style: TextSource.TextStyle, canvasSize: CGSize) -> CIImage? {
        if progress < 0.5 {
            let scale = 1.0 - (progress * 2)
            let image = createTextImage(text: currentWord, style: style, canvasSize: canvasSize)
            return image?.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        } else {
            let scale = (progress - 0.5) * 2
            let image = createTextImage(text: nextWord, style: style, canvasSize: canvasSize)
            return image?.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
    }
    
    private func createTextImage(text: String, style: TextSource.TextStyle, canvasSize: CGSize, offset: CGPoint = .zero) -> CIImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        guard let context = CGContext(data: nil,
                                    width: Int(canvasSize.width),
                                    height: Int(canvasSize.height),
                                    bitsPerComponent: 8,
                                    bytesPerRow: 0,
                                    space: colorSpace,
                                    bitmapInfo: bitmapInfo) else { return nil }
        
        // Set background color if specified
        if let backgroundColor = style.backgroundColor {
            context.setFillColor(backgroundColor)
            context.fill(CGRect(origin: .zero, size: canvasSize))
        }
        
        // Create attributed string with Core Text
        let font = CTFontCreateWithName(style.font as CFString, style.fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: style.color,
            .strokeColor: style.strokeColor ?? CGColor(gray: 0, alpha: 0),
            .strokeWidth: -style.strokeWidth
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()
        
        // Calculate position based on alignment within the canvas
        var drawRect = CGRect(origin: .zero, size: textSize)
        switch style.alignment {
        case .center:
            drawRect.origin.x = max(0, (canvasSize.width - textSize.width) / 2)
        case .right:
            drawRect.origin.x = max(0, canvasSize.width - textSize.width)
        default:
            drawRect.origin.x = 0
        }
        drawRect.origin.y = max(0, (canvasSize.height - textSize.height) / 2)
        
        // Ensure text fits within canvas bounds
        if drawRect.origin.x + textSize.width > canvasSize.width {
            drawRect.origin.x = max(0, canvasSize.width - textSize.width)
        }
        if drawRect.origin.y + textSize.height > canvasSize.height {
            drawRect.origin.y = max(0, canvasSize.height - textSize.height)
        }
        
        // Apply offset
        drawRect.origin.x += offset.x
        drawRect.origin.y += offset.y
        
        // Draw text using Core Text without coordinate flipping
        let line = CTLineCreateWithAttributedString(attributedString)
        context.textPosition = CGPoint(x: drawRect.origin.x, y: drawRect.origin.y)
        CTLineDraw(line, context)
        
        guard let cgImage = context.makeImage() else { return nil }
        return CIImage(cgImage: cgImage)
    }
}
