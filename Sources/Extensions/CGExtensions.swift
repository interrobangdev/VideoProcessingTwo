//
//  CGExtensions.swift
//  VideoProcessingSamples
//
//  Created by Jake Gundersen on 10/21/23.
//

import CoreGraphics
import UIKit

extension CGPoint {
    func distance(otherPoint: CGPoint) -> CGFloat {
        let xDist = abs(otherPoint.x - x)
        let yDist = abs(otherPoint.y - y)
        
        return sqrt(pow(xDist, 2.0) + pow(yDist, 2.0))
    }
    
    static func * (left: CGPoint, right: CGPoint) -> CGPoint {
        return CGPoint(x: left.x * right.x, y: left.y * right.y)
    }
    
    static func * (left: CGPoint, right: CGFloat) -> CGPoint {
        return CGPoint(x: left.x * right, y: left.y * right)
    }
    
    static func / (left: CGPoint, right: CGPoint) -> CGPoint {
        return CGPoint(x: left.x / right.x, y: left.y / right.y)
    }
    
    static func + (left: CGPoint, right: CGPoint) -> CGPoint {
        return CGPoint(x: left.x + right.x, y: left.y + right.y)
    }
    
    static func - (left: CGPoint, right: CGPoint) -> CGPoint {
        return CGPoint(x: left.x - right.x, y: left.y - right.y)
    }
}

extension CGSize {
    static func / (left: CGSize, right: CGFloat) -> CGSize {
        return CGSize(width: left.width / right, height: left.height / right)
    }
    
    static func * (left: CGSize, right: CGFloat) -> CGSize {
        return CGSize(width: left.width * right, height: left.height * right)
    }
    
    static func * ( left : CGSize, right : CGPoint) -> CGPoint {
        return CGPoint(x: left.width * right.x, y: left.height * right.y)
    }
    
    static func * ( left : CGPoint, right : CGSize) -> CGPoint {
        return CGPoint(x: left.x * right.width, y: left.y * right.height)
    }
    
    static func * ( left : CGSize, right : CGSize) -> CGSize {
        return CGSize(width: left.width * right.width, height: left.height * right.height)
    }
    
    static func + (left: CGSize, right: CGSize) -> CGSize {
        return CGSize(width: left.width + right.width, height: left.height + right.height)
    }
    
    static func - (left: CGSize, right: CGSize) -> CGSize {
        return CGSize(width: left.width - right.width, height: left.height - right.height)
    }
}

extension CGRect {
    init(size: CGSize) {
        self.init(origin: .zero, size: size)
    }
    
    static func * (left: CGRect, right: CGFloat) -> CGRect {
        let origin = left.origin * right
        let size = left.size * right
        return CGRect(origin: origin, size: size)
    }
    
    static func * ( left : CGRect, right : CGSize) -> CGRect {
        let origin = left.origin * right
        let size = left.size * right
        return CGRect(origin: origin, size: size)
    }
    
    func area() -> CGFloat {
        return width * height
    }
    
    func center() -> CGPoint {
        return CGPoint(x: origin.x + width / 2.0, y: origin.y + height / 2.0)
    }
    
    func rotateRectAroundCenter(rotation: Double) -> CGRect {
        let center = center()
            
        let tWidth = center.x
        let tHeight = center.y
        
        let translate = CGAffineTransform(translationX: -tWidth, y: -tHeight)
        let rotateT = CGAffineTransform(rotationAngle: rotation)
        var outputRect = CGRectApplyAffineTransform(self, translate)
        outputRect = CGRectApplyAffineTransform(outputRect, rotateT)
        
        let ntWidth = origin.x + outputRect.width / 2.0
        let ntHeight = origin.y + outputRect.height / 2.0
        
        let nTranslate = CGAffineTransform(translationX: ntWidth, y: ntHeight)
        outputRect = CGRectApplyAffineTransform(outputRect, nTranslate)

        return outputRect
    }
}

extension CGAffineTransform {
    var xScale: CGFloat {
        return sqrt(a * a + c * c)
    }
    
    var yScale: CGFloat {
        return sqrt(b * b + d * d)
    }
    
    var rotation: CGFloat {
        return CGFloat(atan2(Double(b), Double(a)))
    }
    
    var xTranslation: CGFloat {
        return tx
    }
    
    var yTranslation: CGFloat {
        return ty
    }
    
    static func flipVertical(height: CGFloat) -> Self {
      CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: height)
    }
}

extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
            case .up: self = .up
            case .upMirrored: self = .upMirrored
            case .down: self = .down
            case .downMirrored: self = .downMirrored
            case .left: self = .left
            case .leftMirrored: self = .leftMirrored
            case .right: self = .right
            case .rightMirrored: self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}

