//
//  PlatformTypes.swift
//  VideoProcessingTwo
//
//  Created by Jake Gundersen on 7/14/25.
//

import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
public typealias PlatformFont = UIFont
public typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
public typealias PlatformFont = NSFont
public typealias PlatformColor = NSColor
#endif

// Cross-platform extensions
extension PlatformImage {
    var cgImageRepresentation: CGImage? {
        #if canImport(UIKit)
        return self.cgImage
        #elseif canImport(AppKit)
        return self.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }
    
    convenience init?(cgImage: CGImage) {
        #if canImport(UIKit)
        self.init(cgImage: cgImage)
        #elseif canImport(AppKit)
        self.init(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
        #endif
    }
}

extension PlatformFont {
    static func systemFont(ofSize size: CGFloat) -> PlatformFont {
        #if canImport(UIKit)
        return UIFont.systemFont(ofSize: size)
        #elseif canImport(AppKit)
        return NSFont.systemFont(ofSize: size)
        #endif
    }
    
    convenience init?(name: String, size: CGFloat) {
        #if canImport(UIKit)
        self.init(name: name, size: size)
        #elseif canImport(AppKit)
        self.init(name: name, size: size)
        #endif
    }
}

extension PlatformColor {
    convenience init(cgColor: CGColor) {
        #if canImport(UIKit)
        self.init(cgColor: cgColor)
        #elseif canImport(AppKit)
        self.init(cgColor: cgColor)!
        #endif
    }
    
    static var clear: PlatformColor {
        #if canImport(UIKit)
        return UIColor.clear
        #elseif canImport(AppKit)
        return NSColor.clear
        #endif
    }
}

// Cross-platform graphics context utilities
public struct PlatformGraphics {
    public static func createImageContext(size: CGSize, opaque: Bool = false, scale: CGFloat = 0.0) -> CGContext? {
        #if canImport(UIKit)
        UIGraphicsBeginImageContextWithOptions(size, opaque, scale)
        return UIGraphicsGetCurrentContext()
        #elseif canImport(AppKit)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        return CGContext(data: nil,
                        width: Int(size.width),
                        height: Int(size.height),
                        bitsPerComponent: 8,
                        bytesPerRow: 0,
                        space: colorSpace,
                        bitmapInfo: bitmapInfo)
        #endif
    }
    
    public static func getImageFromCurrentContext() -> PlatformImage? {
        #if canImport(UIKit)
        return UIGraphicsGetImageFromCurrentImageContext()
        #elseif canImport(AppKit)
        // For AppKit, we need to handle this differently since there's no current context concept
        return nil
        #endif
    }
    
    public static func endImageContext() {
        #if canImport(UIKit)
        UIGraphicsEndImageContext()
        #elseif canImport(AppKit)
        // No-op for AppKit as we manage context manually
        #endif
    }
    
    public static func createImage(from context: CGContext, size: CGSize) -> PlatformImage? {
        guard let cgImage = context.makeImage() else { return nil }
        return PlatformImage(cgImage: cgImage)
    }
}