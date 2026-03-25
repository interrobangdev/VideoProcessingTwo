import CoreImage

/// A filter that can consume one or more auxiliary image inputs in addition to
/// the primary `image` passed to `filterContent(...)`.
public protocol MultiInputFilter: AnyObject, Filter {
    var additionalInputs: [String: CIImage] { get set }
}

public extension MultiInputFilter {
    func inputImage(forKey key: String) -> CIImage? {
        additionalInputs[key]
    }

    func setInputImage(_ image: CIImage?, forKey key: String) {
        if let image {
            additionalInputs[key] = image
        } else {
            additionalInputs.removeValue(forKey: key)
        }
    }
}

/// A filter that keeps internal state between frames (for temporal effects).
public protocol StatefulFilter: Filter {
    func resetState()
}
