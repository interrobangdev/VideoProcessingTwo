import Vision

class VisionTools {
    static func performBodyPoseEstimation(on frame: Frame) -> [VNHumanBodyPoseObservation]? {
        // Create a request to detect human body pose
        let request = VNDetectHumanBodyPoseRequest()
        
        // Get the CIImage representation of the frame
        guard let ciImage = frame.ciImageRepresentation() else {
            print("Failed to get CIImage representation of the frame")
            return nil
        }
        
        // Create a handler to process the image
        let handler = VNImageRequestHandler(ciImage: ciImage, orientation: .up)
        
        do {
            // Perform the request
            try handler.perform([request])
            
            // Get the results
            guard let observations = request.results as? [VNHumanBodyPoseObservation] else {
                print("Failed to get body pose observations")
                return nil
            }
            
            return observations
        } catch {
            print("Error performing body pose estimation: \(error)")
            return nil
        }
    }
    
    func performHandPoseEstimation(on frame: Frame) -> [VNHumanHandPoseObservation]? {
        // Create a request to detect human hand pose
        let request = VNDetectHumanHandPoseRequest()
        
        // Get the CIImage representation of the frame
        guard let ciImage = frame.ciImageRepresentation() else {
            print("Failed to get CIImage representation of the frame")
            return nil
        }
        
        // Create a handler to process the image
        let handler = VNImageRequestHandler(ciImage: ciImage, orientation: .up)
        
        do {
            // Perform the request
            try handler.perform([request])
            
            // Get the results
            guard let observations = request.results as? [VNHumanHandPoseObservation] else {
                print("Failed to get hand pose observations")
                return nil
            }
            
            return observations
        } catch {
            print("Error performing hand pose estimation: \(error)")
            return nil
        }
    }
    
    static func performFaceDetection(on frame: Frame) -> [VNFaceObservation]? {
        let request = VNDetectFaceRectanglesRequest()
        
        guard let ciImage = frame.ciImageRepresentation() else {
            print("Failed to get CIImage representation of the frame")
            return nil
        }
        
        let handler = VNImageRequestHandler(ciImage: ciImage, orientation: .up)
        
        do {
            try handler.perform([request])
            
            guard let observations = request.results as? [VNFaceObservation] else {
                print("Failed to get face observations")
                return nil
            }
            
            return observations
        } catch {
            print("Error performing face detection: \(error)")
            return nil
        }
    }
    
    static func performHumanDetection(on frame: Frame) -> [VNDetectedObjectObservation]? {
        let request = VNDetectHumanRectanglesRequest()
        
        guard let ciImage = frame.ciImageRepresentation() else {
            print("Failed to get CIImage representation of the frame")
            return nil
        }
        
        let handler = VNImageRequestHandler(ciImage: ciImage, orientation: .up)
        
        do {
            try handler.perform([request])
            
            guard let observations = request.results as? [VNDetectedObjectObservation] else {
                print("Failed to get human observations")
                return nil
            }
            
            return observations
        } catch {
            print("Error performing human detection: \(error)")
            return nil
        }
    }
    
#if os(iOS)
    static func performHumanSegmentation(on frame: Frame) -> VNPixelBufferObservation? {
        if #available(iOS 15.0, *) {
            let request = VNGeneratePersonSegmentationRequest()

            guard let ciImage = frame.ciImageRepresentation() else {
                print("Failed to get CIImage representation of the frame")
                return nil
            }
            
            let handler = VNImageRequestHandler(ciImage: ciImage, orientation: .up)
            
            do {
                try handler.perform([request])
                
                guard let observation = request.results?.first as? VNPixelBufferObservation else {
                    print("Failed to get human segmentation observation")
                    return nil
                }
                
                return observation
            } catch {
                print("Error performing human segmentation: \(error)")
                return nil
            }
            
        } else {
            // Fallback on earlier versions
            return nil
        }
    }
#endif
    
    static func performObjectSalienceRequest(on frame: Frame) -> [VNSaliencyImageObservation]? {
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        
        guard let ciImage = frame.ciImageRepresentation() else {
            print("Failed to get CIImage representation of the frame")
            return nil
        }
        
        let handler = VNImageRequestHandler(ciImage: ciImage, orientation: .up)
        
        do {
            try handler.perform([request])
            
            guard let observations = request.results as? [VNSaliencyImageObservation] else {
                print("Failed to get object salience observations")
                return nil
            }
            
            return observations
        } catch {
            print("Error performing object salience request: \(error)")
            return nil
        }
    }
    
    static func performAttentionSaliencyRequest(on frame: Frame) -> [VNSaliencyImageObservation]? {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        
        guard let ciImage = frame.ciImageRepresentation() else {
            print("Failed to get CIImage representation of the frame")
            return nil
        }
        
        let handler = VNImageRequestHandler(ciImage: ciImage, orientation: .up)
        
        do {
            try handler.perform([request])
            
            guard let observations = request.results as? [VNSaliencyImageObservation] else {
                print("Failed to get attention saliency observations")
                return nil
            }
            
            return observations
        } catch {
            print("Error performing attention saliency request: \(error)")
            return nil
        }
    }
}
