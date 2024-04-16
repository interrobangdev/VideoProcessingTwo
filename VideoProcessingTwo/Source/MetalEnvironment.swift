//
//  MetalEnvironment.swift
//  VideoProcessingSamples
//
//  Created by Jake Gundersen on 10/21/23.
//

import Metal
import CoreImage

public class MetalEnvironment {
    //Throw fatal error if we can't initialize this object with Metal Device
    public static let shared: MetalEnvironment = MetalEnvironment()
    
    public var device: MTLDevice
    public var context: CIContext
    
    init() {
        let device = MTLCreateSystemDefaultDevice()!
        self.device = device
        self.context = CIContext(mtlDevice: device)
    }
}
