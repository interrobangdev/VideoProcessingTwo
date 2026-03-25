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
    let scene: VideoScene
    let completion: SceneExportCompletion
    let progress: SceneExportProgress?
}

public class ExportManager {
    var scenesToExport = [ExportModel]()
    let compositor = FrameCompositor()
    var currentlyExporting = false
    
    public static let shared = ExportManager()
    
    public init(scenesToExport: [ExportModel] = [ExportModel](), currentlyExporting: Bool = false) {
        self.scenesToExport = scenesToExport
        self.currentlyExporting = currentlyExporting
    }
    
    
    public func exportScene(scene: VideoScene, outpuURL: URL, progress: SceneExportProgress?, completion: @escaping SceneExportCompletion) {

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

        print(
            "[ExportManager] Starting export scene=\(model.scene.id) " +
            "duration=\(model.scene.duration)s fps=\(model.scene.frameRate) " +
            "output=\(model.outputURL.path)"
        )

        // Run export on background thread to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var lastLoggedProgressBucket = -1
            self?.compositor.exportScene(scene: model.scene, outputType: .video, outputURL: model.outputURL) { (image, time) in
                let progress = time / model.scene.duration
                model.progress?(model.scene.id, progress)

                let progressBucket = Int((progress * 100.0).rounded(.down) / 10.0)
                if progressBucket > lastLoggedProgressBucket {
                    lastLoggedProgressBucket = progressBucket
                    let percent = min(max(progressBucket * 10, 0), 100)
                    print("[ExportManager] scene=\(model.scene.id) progress=\(percent)% time=\(time)s")
                }
            } completion: { [weak self] (success) in
                let fileExists = FileManager.default.fileExists(atPath: model.outputURL.path)
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: model.outputURL.path)[.size] as? NSNumber)?.int64Value ?? 0
                print(
                    "[ExportManager] Finished export scene=\(model.scene.id) " +
                    "success=\(success) fileExists=\(fileExists) fileSize=\(fileSize) " +
                    "output=\(model.outputURL.path)"
                )
                model.completion(success)
                self?.exportNextScene()
            }
        }
    }
}
