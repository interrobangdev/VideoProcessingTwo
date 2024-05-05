//
//  LayerObjectIndex.swift
//  
//
//  Created by Jake Gundersen on 5/4/24.
//

import Foundation

public struct LayerObjectIndex {
    public let groupIndices: [Int]
    public let layerIndex: Int
    
    public init(groupIndices: [Int], layerIndex: Int) {
        self.groupIndices = groupIndices
        self.layerIndex = layerIndex
    }
}
