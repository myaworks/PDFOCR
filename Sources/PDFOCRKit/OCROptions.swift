import Foundation
import Vision

/// How carefully Vision should read the rasterized page.
public enum RecognitionLevel: String, Sendable, CaseIterable, Codable {
    case fast
    case accurate

    var visionLevel: VNRequestTextRecognitionLevel {
        self == .accurate ? .accurate : .fast
    }
}

/// One of the PDF base-14 fonts. None of them need embedding, so the text layer
/// adds no font data to the output.
public enum BaseFont: String, Sendable, CaseIterable, Codable {
    case helvetica
    case times
    case courier
    /// A system font embedded as a subset. The only choice that keeps characters
    /// outside Latin-1 (Turkish ş/ğ, Greek, Cyrillic) readable, at the cost of a
    /// larger file.
    case unicode

    var postScriptName: String {
        switch self {
        case .helvetica: "Helvetica"
        case .times: "Times-Roman"
        case .courier: "Courier"
        case .unicode: "HelveticaNeue"
        }
    }
}

public enum FontSizeMode: Sendable, Equatable {
    /// Point size derived from each recognized line's box height.
    case matchBox
    /// Every line drawn at the same point size.
    case fixed(Double)
}

/// Everything the pipeline can be told to do. The defaults are what you want for
/// a clean 300 dpi scan of Latin-script text.
public struct OCROptions: Sendable {
    public var languages: [String] = ["en-US"]
    public var recognitionLevel: RecognitionLevel = .accurate
    public var dpi: Double = 300
    public var baseFont: BaseFont = .helvetica
    public var fontSizeMode: FontSizeMode = .matchBox
    /// Squeeze each line onto the width of the ink it covers, so selection
    /// highlights line up with the visible glyphs.
    public var squeezeLines: Bool = true
    public var pageSelection: PageSelection = .all
    /// Leave pages that already carry a text layer alone.
    public var skipPagesWithText: Bool = true
    /// Drop a page's existing text layer before writing the new one, by
    /// flattening the page to a bitmap. Use it on re-OCR: otherwise the old and
    /// the new text both survive and search returns both.
    public var replaceExistingText: Bool = false
    public var minimumConfidence: Float = 0
    public var writePlainText: Bool = false
    /// Upper bound on the rasterized page, to keep memory sane on huge sheets.
    public var maxRasterPixels: Int = 40_000_000

    public init() {}
}
