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
    let rotateForDeviceOrientation: Bool

    public init(ciImage: CIImage?, isFrontCamera: Bool = false, rotateForDeviceOrientation: Bool = true) {
        self.ciImage = ciImage
        self.isFrontCamera = isFrontCamera
        self.rotateForDeviceOrientation = rotateForDeviceOrientation
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
        context.coordinator.rotateForDeviceOrientation = rotateForDeviceOrientation
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public class Coordinator: NSObject, MTKViewDelegate {
        var ciImage: CIImage?
        var commandQueue: MTLCommandQueue?
        var isFrontCamera: Bool = false
        var rotateForDeviceOrientation: Bool = true
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

            let drawableRect = CGRect(origin: .zero, size: view.drawableSize)

            // Handle portrait orientation rotation
            let deviceOrientation = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?
                .interfaceOrientation ?? .portrait

            if rotateForDeviceOrientation && (deviceOrientation == .portrait || deviceOrientation == .portraitUpsideDown) {
                ciImage = rotateImageAroundCenter(image: ciImage, rotation: .pi / 2)
            }

            // Mirror image if using front camera (apply after rotation)
            if isFrontCamera {
                let extent = ciImage.extent
                let mirrorTransform = CGAffineTransform(translationX: extent.midX, y: extent.midY)
                    .scaledBy(x: -1, y: 1)
                    .translatedBy(x: -extent.midX, y: -extent.midY)
                ciImage = ciImage.transformed(by: mirrorTransform)
            }

            // Always fit + center into drawable space so the preview is centered.
            let fittedImage = aspectFitCentered(image: ciImage, in: drawableRect)
            let background = CIImage(color: CIColor.black).cropped(to: drawableRect)
            let outputImage = fittedImage.composited(over: background).cropped(to: drawableRect)

            MetalEnvironment.shared.context.render(
                outputImage,
                to: currentDrawable.texture,
                commandBuffer: commandBuffer,
                bounds: drawableRect,
                colorSpace: colorSpace
            )

            commandBuffer.present(currentDrawable)
            commandBuffer.commit()
        }

        private func rotateImageAroundCenter(image: CIImage, rotation: CGFloat) -> CIImage {
            let extent = image.extent
            let center = CGPoint(x: extent.midX, y: extent.midY)
            let transform = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: -rotation)
                .translatedBy(x: -center.x, y: -center.y)
            return image.transformed(by: transform)
        }

        private func aspectFitCentered(image: CIImage, in targetRect: CGRect) -> CIImage {
            let sourceRect = image.extent
            guard
                sourceRect.width > 0, sourceRect.height > 0,
                targetRect.width > 0, targetRect.height > 0
            else { return image }

            let movedToOrigin = image.transformed(
                by: CGAffineTransform(translationX: -sourceRect.minX, y: -sourceRect.minY)
            )

            let scale = min(targetRect.width / sourceRect.width, targetRect.height / sourceRect.height)
            let scaled = movedToOrigin.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let scaledExtent = scaled.extent

            let tx = targetRect.minX + (targetRect.width - scaledExtent.width) * 0.5 - scaledExtent.minX
            let ty = targetRect.minY + (targetRect.height - scaledExtent.height) * 0.5 - scaledExtent.minY
            return scaled.transformed(by: CGAffineTransform(translationX: tx, y: ty))
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
