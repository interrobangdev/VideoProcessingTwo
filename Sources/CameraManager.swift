//
//  CameraManager.swift
//  KNXN
//
//  Created by Jake Gundersen on 5/2/19.
//  Copyright © 2019 Knxn. All rights reserved.
//

import UIKit
import AVFoundation

public protocol CameraManagerDelegate: NSObjectProtocol {
    func didOutputFrame(frame: Frame)
    func didOutputPhotoFrame(photo: CIImage)
}

public class CameraManager : NSObject {
    private let captureSession = AVCaptureSession()
    private var videoDevice: AVCaptureDevice?

    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let photoCaptureOutput = AVCapturePhotoOutput()
    
    var videoInput: AVCaptureDeviceInput?

    let videoDispatchQueue = DispatchQueue(label: "com.VideoProcessingTwo.cameraVideoDataQueue")

    public var outputFrame: Frame?
    public weak var delegate: CameraManagerDelegate?

    public var devicePosition: AVCaptureDevice.Position = .back

    public var exposureBias: Float? {
        get {
            return videoDevice?.exposureTargetBias
        }
    }

    public var minTargetBias: Float {
        var bias: Float = 0.0

        if let dev = videoDevice {
            bias = dev.minExposureTargetBias
        }

        return bias
    }

    public var maxTargetBias: Float {
        var bias: Float = 0.0

        if let dev = videoDevice {
            bias = dev.maxExposureTargetBias
        }

        return bias
    }

    public var minZoom: CGFloat {
        get {
            var zoom: CGFloat = 0.0
            if let d = videoDevice {
                zoom = d.minAvailableVideoZoomFactor
            }
            return zoom
        }
    }

    public var maxZoom: CGFloat {
        get {
            var zoom: CGFloat = 0.0
            if let d = videoDevice {
                zoom = d.maxAvailableVideoZoomFactor
            }
            return zoom
        }
    }

    public var flashMode: AVCaptureDevice.FlashMode = .off
    public var torchMode: AVCaptureDevice.TorchMode = .off
    
    func photoSettings() -> AVCapturePhotoSettings {
        let photoSettings = AVCapturePhotoSettings()
        photoSettings.flashMode = flashMode
        photoSettings.isAutoStillImageStabilizationEnabled = true
        
        return photoSettings
    }
    
    public func setup() {
        videoDevice = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: devicePosition).devices.first

        guard let d = videoDevice else { return }
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high

        if let vi = videoInput {
            captureSession.removeInput(vi)
        }

        do {
            let vi = try AVCaptureDeviceInput(device: d)
            videoInput = vi
            if captureSession.canAddInput(vi) {
                captureSession.addInput(vi)
            }
        } catch let e {
            print("Failed to set up video input \(e)")
        }

        videoDataOutput.setSampleBufferDelegate(self, queue: videoDispatchQueue)

        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        }

        if captureSession.canAddOutput(photoCaptureOutput) {
            captureSession.addOutput(photoCaptureOutput)
        }
        
        captureSession.commitConfiguration()
    }

    public func start() {
        captureSession.startRunning()
    }

    public func stop() {
        captureSession.stopRunning()
    }

    func swapCamera(position: AVCaptureDevice.Position) {
        if devicePosition == position { return }
        devicePosition = position

        setup()
    }

    func isFlashAvailable() -> Bool {
        if let device = videoDevice {
            return device.isFlashAvailable
        }
        
        return false
    }
    
    func isTorchAvailable() -> Bool {
        if let device = videoDevice {
            return device.isTorchAvailable
        }
        
        return false
    }
    
    func switchToVideoMode() {
        setTorchMode(mode: torchMode)
    }
    
    func switchToPhotoMode() {
        //When swapping to photo camera, we want to turn off the torch
        let torchM = torchMode
        //this method alters the 'torchMode' instance variable - so we need to save the previous state
        setTorchMode(mode: .off)
        //but, we want to save the state in the instance variable torchMode, so that when we swap back to
        //video mode, we return to that torch mode
        torchMode = torchM
    }
    
    func setTorchMode(mode: AVCaptureDevice.TorchMode) {
        torchMode = mode

        if let vd = videoDevice {
            do {
                try vd.lockForConfiguration()
                if vd.isTorchModeSupported(mode) {
                    vd.torchMode = mode
                } else {
                    print("Torch mode \(mode.rawValue) unavailable for this camera")
                }
                vd.unlockForConfiguration()
            } catch let e {
                print("Error changing torch mode \(e)")
            }
        }
    }

    func setLockExposureAndFocus(point: CGPoint) {
        //point here is a normalized value between (0, 0) and (1, 1) where
        //(0, 0) is top left and (1, 1) is bottom right in landscape left orientation
        if let vd = videoDevice {
            do {
                try vd.lockForConfiguration()

                if vd.isExposurePointOfInterestSupported {
                    vd.exposurePointOfInterest = point
                } else {
                    print("Exposure point of interest not supported on this camera")
                }

                if vd.isFocusPointOfInterestSupported {
                    vd.focusPointOfInterest = point
                } else {
                    print("Focus point of interest not supported on this camera")
                }

                if vd.isExposureModeSupported(.continuousAutoExposure) {
                    vd.exposureMode = .locked
                } else {
                    print("Exposure mode .locked not supported on this camera")
                }

                if vd.isFocusModeSupported(.continuousAutoFocus) {
                    vd.focusMode = .locked
                } else {
                    print("Focus mode .locked not supported on this camera")
                }

                vd.unlockForConfiguration()
            } catch let e {
                print("Error configuring exposure and focus lock \(e)")
            }
        }
    }

    func setAutoExposureAndFocusPoint(point: CGPoint) {
        //point here is a normalized value between (0, 0) and (1, 1) where
        //(0, 0) is top left and (1, 1) is bottom right in landscape left orientation
        if let vd = videoDevice {
            do {
                try vd.lockForConfiguration()

                if vd.isExposureModeSupported(.continuousAutoExposure) {
                    vd.exposureMode = .continuousAutoExposure
                    vd.setExposureTargetBias(0.0, completionHandler: nil)
                } else {
                    print("Exposure mode .continuousAutoExposure not supported on this camera")
                }

                if vd.isExposurePointOfInterestSupported {
                    vd.exposurePointOfInterest = point
                } else {
                    print("Exposure point of interest not supported on this camera")
                }

                if vd.isFocusModeSupported(.continuousAutoFocus) {
                    vd.focusMode = .continuousAutoFocus
                } else {
                    print("Focus mode .continuousAutoFocus not supported on this camera")
                }

                if vd.isFocusPointOfInterestSupported {
                    vd.focusPointOfInterest = point
                } else {
                    print("Focus point of interest not supported on this camera")
                }

                vd.unlockForConfiguration()
            } catch let e {
                print("Error configuring auto focus point \(e)")
            }
        }
    }

    func setExposureBias(bias: Float) {
        let min = minTargetBias
        let max = maxTargetBias

        guard min < max,
            bias > min,
            bias < max else { return }

        if let vd = videoDevice {
            do {
                try vd.lockForConfiguration()

                vd.setExposureTargetBias(bias, completionHandler: nil)

                vd.unlockForConfiguration()
            } catch let e {
                print("error locking device to set exposure \(e)")
            }
        }
    }

    func setZoom(factor: CGFloat) {
        var f = factor
        if let vd = videoDevice {
            if f > vd.maxAvailableVideoZoomFactor {
                f = vd.maxAvailableVideoZoomFactor
            } else if f < vd.minAvailableVideoZoomFactor {
                f = vd.minAvailableVideoZoomFactor
            }

            do {
                try vd.lockForConfiguration()

                videoDevice?.videoZoomFactor = f

                vd.unlockForConfiguration()
            } catch let e {
                print("Error configuring zoom factor \(e)")
            }
        }
    }
    
    public func takePhoto() {
        let photoSets = photoSettings()
        photoCaptureOutput.capturePhoto(with: photoSets, delegate: self)
    }
}

extension CameraManager : AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let frame = VideoFrame(pixelBuffer: pixelBuffer, time: sampleBuffer.presentationTimeStamp)
            
            DispatchQueue.main.async { [weak self] in
                self?.outputFrame = frame
                self?.delegate?.didOutputFrame(frame: frame)
            }
        }
    }

    public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let presentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        print("Did drop sample buffer \(CMTimeGetSeconds(presentTime))")
    }
}

extension CameraManager : AVCapturePhotoCaptureDelegate {
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let cgImg = photo.cgImageRepresentation() {
            let image = CIImage(cgImage: cgImg)
            delegate?.didOutputPhotoFrame(photo: image)
        }
    }
}
