//
//  MetalView.swift
//  VideoProcessingTwo
//
//  SwiftUI wrapper for Metal-based image rendering
//

import SwiftUI
import MetalKit
import CoreImage

/// A SwiftUI view that displays a CIImage using Metal rendering
public struct MetalView: UIViewRepresentable {
    let ciImage: CIImage?
    let isFrontCamera: Bool

    public init(ciImage: CIImage?, isFrontCamera: Bool = false) {
        self.ciImage = ciImage
        self.isFrontCamera = isFrontCamera
    }

    public func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()

        // Configure Metal using MetalEnvironment (same as MetalViewController)
        mtkView.device = MetalEnvironment.shared.device
        mtkView.delegate = context.coordinator

        // Key setting: allow rendering to the drawable texture
        mtkView.framebufferOnly = false

        // Setup command queue
        if let device = mtkView.device {
            context.coordinator.commandQueue = device.makeCommandQueue()
        }

        mtkView.backgroundColor = .clear
        mtkView.layer.backgroundColor = UIColor.clear.cgColor

        return mtkView
    }

    public func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.ciImage = ciImage
        context.coordinator.isFrontCamera = isFrontCamera
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public class Coordinator: NSObject, MTKViewDelegate {
        var ciImage: CIImage?
        var commandQueue: MTLCommandQueue?
        var isFrontCamera: Bool = false
        private let colorSpace = CGColorSpaceCreateDeviceRGB()

        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // Handle size changes
        }

        public func draw(in view: MTKView) {
            guard let currentDrawable = view.currentDrawable,
                  let commandQueue = commandQueue,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  var ciImage = ciImage else {
                return
            }

            // Handle portrait orientation rotation
            let deviceOrientation = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?
                .interfaceOrientation ?? .portrait

            if deviceOrientation == .portrait || deviceOrientation == .portraitUpsideDown {
                ciImage = rotateAndScaleImage(image: ciImage, size: view.drawableSize, rotation: .pi / 2)
            }

            // Mirror image if using front camera (apply after rotation)
            if isFrontCamera {
                let mirrorTransform = CGAffineTransform(scaleX: -1, y: 1)
                    .translatedBy(x: -ciImage.extent.width, y: 0)
                ciImage = ciImage.transformed(by: mirrorTransform)
            }

            // Render the CIImage to fill the entire drawable area
            let drawableRect = CGRect(origin: .zero, size: view.drawableSize)
            MetalEnvironment.shared.context.render(
                ciImage,
                to: currentDrawable.texture,
                commandBuffer: commandBuffer,
                bounds: ciImage.extent,
                colorSpace: colorSpace
            )

            commandBuffer.present(currentDrawable)
            commandBuffer.commit()
        }

        private func rotateAndScaleImage(image: CIImage, size: CGSize, rotation: CGFloat) -> CIImage {
            let originalSize = image.extent.size

            // Translate to origin
            let originTranslate = CGAffineTransform(translationX: -originalSize.width / 2.0, y: -originalSize.height / 2.0)
            let centeredImage = image.transformed(by: originTranslate)

            // Rotate
            let rotationTransform = CGAffineTransform(rotationAngle: -rotation)
            let rotatedImage = centeredImage.transformed(by: rotationTransform)

            // Calculate scale to fit in view
            var scale = CGVector(dx: size.width / originalSize.width, dy: size.height / originalSize.height)
            if abs(rotation) == CGFloat.pi / 2 {
                scale = CGVector(dx: size.width / originalSize.height, dy: size.height / originalSize.width)
            }

            var scl = scale.dx
            if scale.dx > scale.dy {
                scl = scale.dy
            }

            let scaleTransform = CGAffineTransform(scaleX: scl, y: scl)
            let scaledImage = rotatedImage.transformed(by: scaleTransform)

            // Translate to center
            let origin = scaledImage.extent.origin
            let translation = CGAffineTransform(translationX: -origin.x, y: -origin.y)
            let translated = scaledImage.transformed(by: translation)

            // Composite over black background and crop to drawable size
            let blackBackground = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1))
                .cropped(to: CGRect(origin: .zero, size: size))
            let composited = translated.composited(over: blackBackground)

            return composited.cropped(to: CGRect(origin: .zero, size: size))
        }
    }
}

// Preview for development
#if DEBUG
struct MetalView_Previews: PreviewProvider {
    static var previews: some View {
        // Create a simple test image
        let ciImage = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.8))
            .cropped(to: CGRect(x: 0, y: 0, width: 300, height: 400))

        MetalView(ciImage: ciImage)
            .frame(height: 400)
    }
}
#endif
