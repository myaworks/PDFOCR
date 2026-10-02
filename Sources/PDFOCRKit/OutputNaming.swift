import Foundation

public extension URL {
    /// The default output for `source`: the same name with "-ocr" before the
    /// extension, in the same directory.
    ///
    /// Note the `deletingLastPathComponent()` — appending to a file URL treats
    /// the existing path as a directory and nests the new name inside it.
    func appendingOCRSuffix() -> URL {
        let stem = deletingPathExtension().lastPathComponent
        let name = stem + "-ocr" + (pathExtension.isEmpty ? ".pdf" : ".\(pathExtension)")
        return deletingLastPathComponent().appendingPathComponent(name)
    }
}
