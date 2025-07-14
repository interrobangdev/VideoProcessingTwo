//
//  MetalDisplayView.swift
//
//  Created by Jake Gundersen on 4/2/21.
//

import UIKit
import MetalKit

open class MetalViewController: UIViewController {
    public var image: CIImage?
    private var colorSpace = CGColorSpaceCreateDeviceRGB()
    private var commandQueue: MTLCommandQueue?
    public var metalView: MTKView?
    
    public var videoSize: CGSize = .zero {
        didSet {
            let aspect = view.frame.width / view.frame.height

            let pixelSize = CGSize(width: videoSize.width, height: videoSize.width / aspect)
            metalView?.drawableSize = pixelSize
        }
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        
        setupMetal()
        
        for v in view.subviews {
            if v != metalView {
                view.bringSubviewToFront(v)
            }
        }
        
        view.backgroundColor = .black
    }
    
    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let metalFrame = view.bounds.insetBy(dx: 0.0, dy: 40.0)
        metalView?.frame = metalFrame
        let scale = UIScreen.main.nativeScale
        let size = CGSize(width: metalFrame.width * scale, height: metalFrame.height * scale)
        metalView?.drawableSize = size
        if let mv = metalView {
            view.bringSubviewToFront(mv)
        }
    }
    
    private func setupMetal() {
        view.backgroundColor = .clear
        
        let mv = MTKView(frame: view.bounds.insetBy(dx: 20.0, dy: 20.0))
        metalView = mv
        view.addSubview(mv)
        mv.frame = view.bounds.insetBy(dx: 20.0, dy: 20.0)
        
        metalView?.device = MetalEnvironment.shared.device
        commandQueue = metalView?.device?.makeCommandQueue()

        metalView?.framebufferOnly = false
        
        metalView?.backgroundColor = .clear
        metalView?.layer.backgroundColor = UIColor.clear.cgColor
        view.backgroundColor = .clear
        
        metalView?.delegate = self
    }
    
    open func processImage() {
        //override in subclass
    }
}

extension MetalViewController: MTKViewDelegate {
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        print("changed drawable size \(size)")
        //NO-op
    }

    public func draw(in view: MTKView) {
        if let currentDrawable = view.currentDrawable,
            let commandQueue = commandQueue,
            let commandBuffer = commandQueue.makeCommandBuffer() {

            processImage()
            
            var outputImage = image
            if let drawSize = metalView?.drawableSize,
                let oi = outputImage {
//              iPhone Portrait rotation
                outputImage = rotateAndScaleImage(image: oi, size: drawSize, rotation: M_PI_2)
            }
            
            if let frame = outputImage {
                MetalEnvironment.shared.context.render(frame,
                                                         to: currentDrawable.texture,
                                                         commandBuffer: commandBuffer,
                                                         bounds: frame.extent,
                                                         colorSpace: colorSpace)
                commandBuffer.present(currentDrawable)
                commandBuffer.commit()
            }
        }
    }
    
    private func rotateAndScaleImage(image: CIImage, size: CGSize, rotation: Double) -> CIImage {
        let originalSize = image.extent.size
        //let rotatedOriginalSize = CGSize(width: originalSize.height, height: originalSize.width)

        let originTranslate = CGAffineTransform(translationX: -originalSize.width / 2.0, y: -originalSize.height / 2.0)
        let centeredImage = image.transformed(by: originTranslate)

        let rotationTransform = CGAffineTransform(rotationAngle: -CGFloat(rotation))
        let rotatedImage = centeredImage.transformed(by: rotationTransform)
        
        var scale = CGVector(dx: size.width / originalSize.width, dy: size.height / originalSize.height)
        if abs(rotation) == M_PI_2 {
            scale = CGVector(dx: size.width / originalSize.height, dy: size.height / originalSize.width)
        }

        var scl = scale.dx
        if scale.dx > scale.dy {
            scl = scale.dy
        }
        
        let scaleTransform = CGAffineTransform(scaleX: scl, y: scl)
        let scaledImage = rotatedImage.transformed(by: scaleTransform)
//        print("scaled \(scaledImage.extent)")
        let scaledSize = CGSize(width: originalSize.width * scl, height: originalSize.height * scl)
//        let diff = CGSize(width: scaledSize.width - size.width, height: scaledSize.height - size.height)
        let origin = scaledImage.extent.origin
        
        let translation = CGAffineTransform(translationX: -origin.x, y: -origin.y)
        let translated = scaledImage.transformed(by: translation)
        
        let cropped = translated.cropped(to: CGRect(origin: .zero, size: translated.extent.size))
//        print("translated \(translated.extent)")
//        print("cropped \(cropped.extent)")
        return cropped
    }
}
