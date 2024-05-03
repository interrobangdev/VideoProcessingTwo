//
//  ExportManager.swift
//
//
//  Created by Jake Gundersen on 4/27/24.
//

import Foundation

public typealias SceneExportProgress = (String, Double) -> ()
public typealias SceneExportCompletion = (Bool) -> ()

public struct ExportModel {
    let outputURL: URL
    let scene: Scene
    let completion: SceneExportCompletion
    let progress: SceneExportProgress?
}

public class ExportManager {
    var scenesToExport = [ExportModel]()
    let compositor = FrameCompositor()
    var currentlyExporting = false
    
    public static let shared = ExportManager()
    
    public func exportScene(scene: Scene, outpuURL: URL, progress: SceneExportProgress?, completion: @escaping SceneExportCompletion) {
        
        let model = ExportModel(outputURL: outpuURL, scene: scene, completion: completion, progress: progress)
        scenesToExport.append(model)
        
        exportScenes()
    }
    
    func exportScenes() {
        if currentlyExporting { return }
        currentlyExporting = true
        
        exportNextScene()
    }
    
    func exportNextScene() {
        guard let model = scenesToExport.first else {
            currentlyExporting = false
            return
        }
        scenesToExport.removeFirst()
        
        compositor.exportScene(scene: model.scene, outputType: .video, outputURL: model.outputURL) { (image, time) in
            let progress = time / model.scene.duration
            model.progress?(model.scene.id, progress)
        } completion: { [weak self] (success) in
            model.completion(success)
            self?.exportNextScene()
        }
    }
}
