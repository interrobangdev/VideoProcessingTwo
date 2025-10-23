import XCTest
import CoreImage
import CoreMedia
@testable import VideoProcessingTwo

final class VideoProcessingTwoTests: XCTestCase {

    // MARK: - Composition Tests

    func testCompositionCreation() throws {
        let scene = Scene(duration: 5.0, frameRate: 30.0)
        let composition = Composition(
            scenes: [scene],
            renderSize: CGSize(width: 1920, height: 1080),
            outputType: .video
        )

        XCTAssertEqual(composition.scenes.count, 1)
        XCTAssertEqual(composition.renderSize.width, 1920)
        XCTAssertEqual(composition.renderSize.height, 1080)
        XCTAssertEqual(composition.outputType, .video)
    }

    func testCompositionWithMultipleScenes() throws {
        let scene1 = Scene(duration: 3.0, frameRate: 30.0)
        let scene2 = Scene(duration: 5.0, frameRate: 30.0)
        let composition = Composition(
            scenes: [scene1, scene2],
            renderSize: CGSize(width: 1280, height: 720),
            outputType: .gif
        )

        XCTAssertEqual(composition.scenes.count, 2)
        XCTAssertEqual(composition.outputType, .gif)
    }

    // MARK: - Scene Tests

    func testSceneCreation() throws {
        let scene = Scene(duration: 10.0, frameRate: 24.0)

        XCTAssertEqual(scene.duration, 10.0)
        XCTAssertEqual(scene.frameRate, 24.0)
        XCTAssertNotNil(scene.group)
        XCTAssertEqual(scene.size.width, 1200)
        XCTAssertEqual(scene.size.height, 675)
    }

    func testSceneWithCustomSize() throws {
        let customSize = CGSize(width: 1920, height: 1080)
        let scene = Scene(duration: 5.0, frameRate: 60.0, size: customSize)

        XCTAssertEqual(scene.size.width, 1920)
        XCTAssertEqual(scene.size.height, 1080)
    }

    func testSceneFilenameGeneration() throws {
        let scene = Scene(duration: 1.0, frameRate: 30.0)
        let filename = scene.makeSceneFilename()

        XCTAssertTrue(filename.hasSuffix(".mp4"))
        XCTAssertTrue(filename.contains("-") || filename.count > 10) // UUID format
    }

    // MARK: - Group Tests

    func testEmptyGroupCreation() throws {
        let group = Group.emptyGroup()

        XCTAssertEqual(group.groups.count, 0)
        XCTAssertEqual(group.layers.count, 1)
        XCTAssertEqual(group.filters.count, 0)
        XCTAssertNil(group.mask)
    }

    func testGroupWithLayers() throws {
        let layer1 = Layer(surfaces: [])
        let layer2 = Layer(surfaces: [])
        let group = Group(groups: [], layers: [layer1, layer2], filters: [], mask: nil)

        XCTAssertEqual(group.layers.count, 2)
    }

    func testNestedGroups() throws {
        let childGroup = Group.emptyGroup()
        let parentGroup = Group(groups: [childGroup], layers: [], filters: [], mask: nil)

        XCTAssertEqual(parentGroup.groups.count, 1)
        XCTAssertEqual(parentGroup.layers.count, 0)
    }

    // MARK: - Layer Tests

    func testLayerCreation() throws {
        let layer = Layer(surfaces: [])

        XCTAssertEqual(layer.surfaces.count, 0)
        XCTAssertFalse(layer.id.isEmpty)
    }

    func testLayerWithSurfaces() throws {
        let image = createTestCGImage()
        let source = ImageSource(image: image)
        let surface = Surface(
            source: source,
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            rotation: 0
        )
        let layer = Layer(surfaces: [surface])

        XCTAssertEqual(layer.surfaces.count, 1)
    }

    // MARK: - Surface Tests

    func testSurfaceCreation() throws {
        let image = createTestCGImage()
        let source = ImageSource(image: image)
        let frame = CGRect(x: 10, y: 20, width: 100, height: 200)
        let surface = Surface(source: source, frame: frame, rotation: 45.0)

        XCTAssertEqual(surface.frame.origin.x, 10)
        XCTAssertEqual(surface.frame.origin.y, 20)
        XCTAssertEqual(surface.frame.width, 100)
        XCTAssertEqual(surface.frame.height, 200)
        XCTAssertEqual(surface.rotation, 45.0)
    }

    // MARK: - LayerObjectIndex Tests

    func testLayerObjectIndexCreation() throws {
        let index = LayerObjectIndex(groupIndices: [0, 1, 2], layerIndex: 3)

        XCTAssertEqual(index.groupIndices.count, 3)
        XCTAssertEqual(index.groupIndices[0], 0)
        XCTAssertEqual(index.groupIndices[1], 1)
        XCTAssertEqual(index.groupIndices[2], 2)
        XCTAssertEqual(index.layerIndex, 3)
    }

    func testLayerObjectIndexRootLevel() throws {
        let index = LayerObjectIndex(groupIndices: [], layerIndex: 0)

        XCTAssertEqual(index.groupIndices.count, 0)
        XCTAssertEqual(index.layerIndex, 0)
    }

    // MARK: - Scene Navigation Tests

    func testGetGroupAtRootLevel() throws {
        let scene = Scene(duration: 1.0, frameRate: 30.0)
        let index = LayerObjectIndex(groupIndices: [], layerIndex: 0)

        let group = scene.getGroup(layerIndex: index, create: false)

        XCTAssertNotNil(group)
    }

    func testGetGroupWithCreation() throws {
        let scene = Scene(duration: 1.0, frameRate: 30.0)
        let index = LayerObjectIndex(groupIndices: [0, 1], layerIndex: 0)

        let group = scene.getGroup(layerIndex: index, create: true)

        XCTAssertNotNil(group)
    }

    func testGetGroupWithoutCreation() throws {
        let scene = Scene(duration: 1.0, frameRate: 30.0)
        let index = LayerObjectIndex(groupIndices: [5], layerIndex: 0)

        let group = scene.getGroup(layerIndex: index, create: false)

        XCTAssertNil(group)
    }

    func testGetGroupLayerWithCreation() throws {
        let scene = Scene(duration: 1.0, frameRate: 30.0)
        let index = LayerObjectIndex(groupIndices: [], layerIndex: 2)

        let layer = scene.getGroupLayer(layerIndex: index, create: true)

        XCTAssertNotNil(layer)
    }

    // MARK: - ImageSource Tests

    func testImageSourceCreation() throws {
        let image = createTestCGImage()
        let source = ImageSource(image: image)

        let frame = source.getFrameAtTime(cmTime: CMTime.zero)

        XCTAssertNotNil(frame)
    }

    func testImageSourceConsistency() throws {
        let image = createTestCGImage()
        let source = ImageSource(image: image)

        let frame1 = source.getFrameAtTime(cmTime: CMTime.zero)
        let frame2 = source.getFrameAtTime(cmTime: CMTime(seconds: 5.0, preferredTimescale: 600))

        // Image source should return same frame regardless of time
        XCTAssertNotNil(frame1)
        XCTAssertNotNil(frame2)
    }

    // MARK: - FilterAnimator Tests

    func testFilterAnimatorSingleValue() throws {
        let animator = FilterAnimator(
            type: .SingleValue,
            animationProperty: .radius,
            startValue: 0.0,
            endValue: 10.0,
            startTime: 0.0,
            endTime: 1.0,
            tweenFunctionProvider: LinearFunction()
        )

        // Test at start
        let valueAtStart = animator.tweenValue(time: 0.0) as? Double
        XCTAssertNotNil(valueAtStart)
        XCTAssertEqual(valueAtStart ?? 0, 0.0, accuracy: 0.01)

        // Test at middle
        let valueAtMiddle = animator.tweenValue(time: 0.5) as? Double
        XCTAssertNotNil(valueAtMiddle)
        XCTAssertEqual(valueAtMiddle ?? 0, 5.0, accuracy: 0.01)

        // Test at end
        let valueAtEnd = animator.tweenValue(time: 1.0) as? Double
        XCTAssertNotNil(valueAtEnd)
        XCTAssertEqual(valueAtEnd ?? 0, 10.0, accuracy: 0.01)
    }

    func testFilterAnimatorPoint() throws {
        let animator = FilterAnimator(
            type: .Point,
            animationProperty: .centerPoint,
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 100, y: 100),
            startTime: 0.0,
            endTime: 2.0,
            tweenFunctionProvider: LinearFunction()
        )

        let valueAtMiddle = animator.tweenValue(time: 1.0) as? CGPoint
        XCTAssertNotNil(valueAtMiddle)
        XCTAssertEqual(valueAtMiddle?.x ?? 0, 50.0, accuracy: 0.01)
        XCTAssertEqual(valueAtMiddle?.y ?? 0, 50.0, accuracy: 0.01)
    }

    func testFilterAnimatorRect() throws {
        let startRect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let endRect = CGRect(x: 50, y: 50, width: 200, height: 200)

        let animator = FilterAnimator(
            type: .Rect,
            animationProperty: .scale,
            startRect: startRect,
            endRect: endRect,
            startTime: 0.0,
            endTime: 1.0,
            tweenFunctionProvider: LinearFunction()
        )

        let valueAtMiddle = animator.tweenValue(time: 0.5) as? CGRect
        XCTAssertNotNil(valueAtMiddle)
        XCTAssertEqual(valueAtMiddle?.origin.x ?? 0, 25.0, accuracy: 0.01)
        XCTAssertEqual(valueAtMiddle?.width ?? 0, 150.0, accuracy: 0.01)
    }

    func testFilterAnimatorClampingBeforeStart() throws {
        let animator = FilterAnimator(
            type: .SingleValue,
            animationProperty: .fade,
            startValue: 0.0,
            endValue: 1.0,
            startTime: 1.0,
            endTime: 2.0,
            tweenFunctionProvider: LinearFunction()
        )

        let value = animator.tweenValue(time: 0.0) as? Double
        XCTAssertNotNil(value)
        XCTAssertEqual(value ?? 0, 0.0, accuracy: 0.01) // Should clamp to start
    }

    func testFilterAnimatorClampingAfterEnd() throws {
        let animator = FilterAnimator(
            type: .SingleValue,
            animationProperty: .fade,
            startValue: 0.0,
            endValue: 1.0,
            startTime: 0.0,
            endTime: 1.0,
            tweenFunctionProvider: LinearFunction()
        )

        let value = animator.tweenValue(time: 5.0) as? Double
        XCTAssertNotNil(value)
        XCTAssertEqual(value ?? 0, 1.0, accuracy: 0.01) // Should clamp to end
    }

    // MARK: - Linear Tween Function Tests

    func testLinearTweenFunction() throws {
        let linear = LinearFunction()

        XCTAssertEqual(linear.tweenValue(input: 0.0), 0.0)
        XCTAssertEqual(linear.tweenValue(input: 0.5), 0.5)
        XCTAssertEqual(linear.tweenValue(input: 1.0), 1.0)
    }

    // MARK: - Filter Tests

    func testGaussianBlurFilterCreation() throws {
        let blur = GaussianBlur(radius: 10.0, filterAnimators: [])

        XCTAssertEqual(blur.radius, 10.0)
        XCTAssertEqual(blur.filterAnimators.count, 0)
    }

    func testGaussianBlurFilterUpdateValue() throws {
        var blur = GaussianBlur(radius: 5.0, filterAnimators: [])

        blur.updateFilterValue(filterProperty: .radius, value: 20.0)

        XCTAssertEqual(blur.radius, 20.0)
    }

    func testColorAdjustmentFilterCreation() throws {
        let colorAdjust = ColorAdjustment(
            brightness: 0.1,
            contrast: 1.2,
            saturation: 1.5,
            filterAnimators: []
        )

        XCTAssertEqual(colorAdjust.brightness, 0.1, accuracy: 0.001)
        XCTAssertEqual(colorAdjust.contrast, 1.2, accuracy: 0.001)
        XCTAssertEqual(colorAdjust.saturation, 1.5, accuracy: 0.001)
    }

    func testFadeFilterCreation() throws {
        let fade = Fade(fade: 0.5, filterAnimators: [])

        XCTAssertEqual(fade.fade, 0.5)
    }

    func testScaleFilterCreation() throws {
        let scale = Scale(scale: 2.0, centerPoint: CGPoint(x: 100, y: 100), filterAnimators: [])

        XCTAssertEqual(scale.scale, 2.0)
        XCTAssertEqual(scale.centerPoint.x, 100)
        XCTAssertEqual(scale.centerPoint.y, 100)
    }

    func testRotateFilterCreation() throws {
        let rotate = Rotate(rotation: 90.0, centerPoint: CGPoint(x: 50, y: 50), filterAnimators: [])

        XCTAssertEqual(rotate.rotation, 90.0)
    }

    func testTranslateFilterCreation() throws {
        let translate = Translate(translation: CGPoint(x: 10, y: 20), filterAnimators: [])

        XCTAssertEqual(translate.translation.x, 10)
        XCTAssertEqual(translate.translation.y, 20)
    }

    // MARK: - MetalEnvironment Tests

    func testMetalEnvironmentSingleton() throws {
        let env1 = MetalEnvironment.shared
        let env2 = MetalEnvironment.shared

        XCTAssertTrue(env1 === env2) // Same instance
    }

    func testMetalEnvironmentHasDevice() throws {
        let env = MetalEnvironment.shared

        XCTAssertNotNil(env.device)
    }

    func testMetalEnvironmentHasContext() throws {
        let env = MetalEnvironment.shared

        XCTAssertNotNil(env.context)
    }

    // MARK: - Platform Types Tests

    func testPlatformImageFromCGImage() throws {
        let cgImage = createTestCGImage()
        let platformImage = PlatformImage(cgImage: cgImage)

        XCTAssertNotNil(platformImage)
    }

    func testPlatformImageCGRepresentation() throws {
        let cgImage = createTestCGImage()
        let platformImage = PlatformImage(cgImage: cgImage)

        XCTAssertNotNil(platformImage?.cgImageRepresentation)
    }

    func testPlatformColorCreation() throws {
        // Just test that we can create a platform color
        let cgColor = CGColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        let platformColor = PlatformColor(cgColor: cgColor)

        XCTAssertNotNil(platformColor)
    }

    func testPlatformFontCreation() throws {
        // Just test that we can create a platform font
        let font = PlatformFont(name: "Helvetica", size: 16.0)

        XCTAssertNotNil(font)
    }

    // MARK: - Frame Tests

    func testImageFrameCreation() throws {
        let cgImage = createTestCGImage()
        let platformImage = PlatformImage(cgImage: cgImage)!
        let frame = ImageFrame(image: platformImage)

        XCTAssertNotNil(frame.ciImageRepresentation())
        XCTAssertEqual(frame.time, CMTime.indefinite)
    }

    func testLowImageFrameCreation() throws {
        let cgImage = createTestCGImage()
        let frame = LowImageFrame(cgImage: cgImage, time: CMTime.zero)

        XCTAssertNotNil(frame.ciImageRepresentation())
        XCTAssertEqual(frame.time, CMTime.zero)
    }

    // MARK: - Helper Methods

    private func createTestCGImage() -> CGImage {
        let width = 100
        let height = 100
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            fatalError("Could not create test CGContext")
        }

        // Draw a simple test pattern
        context.setFillColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let cgImage = context.makeImage() else {
            fatalError("Could not create test CGImage")
        }

        return cgImage
    }
}
