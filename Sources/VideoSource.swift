//
//  VideoSource.swift
//  VideoProcessingTwo
//
//  Created by Jake Gundersen on 4/22/24.
//

import Foundation
import CoreMedia

public class VideoSource: Source {
    var lastFrame: Frame?
    var currentFrame: Frame?
    
    var reader: MovieReader?
    let url: URL
    
    public init(movieFileUrl: URL) {
        url = movieFileUrl
        
        setupReader(movieFileURL: movieFileUrl)
    }
    
    func setupReader(movieFileURL: URL) {
        self.reader = MovieReader(url: movieFileURL)
        
        let success = reader?.setupReader()
        
        if let frame = reader?.getNextPixelBuffer() {
            lastFrame = frameFromVideoReaderFrame(frame: frame)
        }
        if let frm = reader?.getNextPixelBuffer() {
            currentFrame = frameFromVideoReaderFrame(frame: frm)
        }
    }
    
    public func getFrameAtTime(cmTime: CMTime) -> (any Frame)? {
        let loopedTime = cmTime.seconds.remainder(dividingBy: reader?.duration ?? 1.0).cmTime()
        guard let lf = lastFrame,
              let cf = currentFrame else { return nil }
        if loopedTime >= lf.time && loopedTime < cf.time {
            return lf
        } else {
            lastFrame = currentFrame
            if let frame = reader?.getNextPixelBuffer() {
                currentFrame = frameFromVideoReaderFrame(frame: frame)
                return currentFrame
            } else {
                setupReader(movieFileURL: url)
                return lastFrame
            }
        }
    }
    
    func frameFromVideoReaderFrame(frame: VideoReaderFrame) -> VideoFrame {
        return VideoFrame(pixelBuffer: frame.pixelBuffer, time: frame.timeStamp)
    }
}
