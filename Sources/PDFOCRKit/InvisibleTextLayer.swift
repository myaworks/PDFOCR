import CoreGraphics
import CoreText
import Foundation

/// What the text layer ended up containing, so the caller can warn about text
/// the chosen font cannot represent.
struct TextLayerStats {
    var lines = 0
    var unmappedCharacters = 0
}

/// Draws recognized text into a PDF content stream in *invisible* render mode.
/// That is what makes a scanned page selectable and searchable while the scan
/// underneath stays untouched.
enum InvisibleTextLayer {
        /// Characters that CoreText folds onto a preceding `f`. Which ones depends
    /// on the font — the base-14 faces fold `fi`, `fl`, `ffi` and `ffl`, and
    /// only some of them also fold a bare `ff` — so the union is used and the
    /// runs are broken wherever any of them could apply.
    private static let ligatureTails: Set<Character> = ["f", "i", "l", "t"]

    /// Offsets, in Characters, where the attributed runs must break.
    static func runBoundaries(in text: String) -> [Int] {
        var boundaries: [Int] = []
        var previous: Character?
        for (offset, character) in text.enumerated() {
            if previous == "f", ligatureTails.contains(character) {
                boundaries.append(offset)
            }
            previous = character
        }
        return boundaries
    }

    @discardableResult
    static func draw(
        lines: [RecognizedLine],
        displaySize: CGSize,
        mediaBox: CGRect,
        rotation: Int,
        options: OCROptions,
        in context: CGContext
    ) -> TextLayerStats {
        var stats = TextLayerStats()
        guard !lines.isEmpty else { return stats }

        let width = displaySize.width
        let height = displaySize.height
        let fontName = options.baseFont.postScriptName as CFString

        context.saveGState()
        context.setTextDrawingMode(.invisible)
        context.textPosition = .zero
        context.textMatrix = .identity
        context.concatenate(
            PageGeometry.displayToPageTransform(mediaBox: mediaBox, rotation: rotation)
        )

        for line in lines {
            let boxHeight = Double(line.box.height) * height
            guard boxHeight > 0.5, boxHeight < 400 else { continue }

            let pointSize: CGFloat
            switch options.fontSizeMode {
            case .matchBox: pointSize = CGFloat(boxHeight)
            case .fixed(let value): pointSize = CGFloat(value)
            }

            let font = CTFontCreateWithName(fontName, pointSize, nil)
            stats.unmappedCharacters += unmappedCharacters(in: line.text, font: font)

            let ctLine = CTLineCreateWithAttributedString(
                attributedString(for: line.text, size: pointSize, fontName: fontName)
            )

            var advance: CGFloat = 0
            CTLineGetTypographicBounds(ctLine, nil, nil, &advance)

            var squeeze: CGFloat = 1
            if options.squeezeLines, advance > 0 {
                let target = CGFloat(line.box.width) * width
                squeeze = min(max(target / advance, 0.4), 2.5)
            }

            let originX = CGFloat(line.box.minX) * width
            let baselineY = (CGFloat(line.box.minY) + CGFloat(line.box.height) * 0.80) * height

            context.textMatrix = CGAffineTransform(a: squeeze, b: 0, c: 0, d: 1, tx: originX, ty: baselineY)
            CTLineDraw(ctLine, context)
            stats.lines += 1
        }

        context.restoreGState()
        return stats
    }

    /// One line, one text object, broken into attributed runs only where a
    /// ligature would otherwise form.
    ///
    /// Drawing the pieces as separate lines instead would be simpler, but then
    /// each piece carries its own side bearings with no kerning to absorb them;
    /// a reader sees a gap and inserts a space, turning "defined" into
    /// "de f i nes". Inside a single line CoreText emits the compensating
    /// `TJ` adjustments and the word stays whole.
    ///
    /// The runs differ by a hundredth of a percent in point size, which is
    /// invisible and just enough for CoreText to treat them as separate runs —
    /// and adjacent runs never ligate.
    private static func attributedString(
        for text: String,
        size: CGFloat,
        fontName: CFString
    ) -> NSAttributedString {
        let boundaries = runBoundaries(in: text)
        guard !boundaries.isEmpty else {
            let font = CTFontCreateWithName(fontName, size, nil)
            return NSAttributedString(
                string: text,
                attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
            )
        }

        let result = NSMutableAttributedString()
        var cursor = 0
        var run = 0
        for boundary in boundaries + [text.count] {
            let start = text.index(text.startIndex, offsetBy: cursor)
            let end = text.index(text.startIndex, offsetBy: boundary)
            let font = CTFontCreateWithName(
                fontName,
                run.isMultiple(of: 2) ? size : size * 1.0001,
                nil
            )
            result.append(NSAttributedString(
                string: String(text[start..<end]),
                attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
            ))
            cursor = boundary
            run += 1
        }
        return result
    }

    /// Characters the font has no glyph for; they will not survive in the file.
    private static func unmappedCharacters(in text: String, font: CTFont) -> Int {
        let units = Array(text.utf16)
        guard !units.isEmpty else { return 0 }
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        units.withUnsafeBufferPointer { buffer in
            _ = CTFontGetGlyphsForCharacters(font, buffer.baseAddress!, &glyphs, units.count)
        }
        return glyphs.reduce(into: 0) { count, glyph in
            if glyph == 0 { count += 1 }
        }
    }
}