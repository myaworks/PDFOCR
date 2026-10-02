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
    /// Pairs CoreText would fold into one glyph. A PDF base-14 encoding has no
    /// code for the ﬁ/ﬀ/ﬂ characters, so a line that gets shaped as a whole ends
    /// up in the file as an unsearchable ligature. Drawing the line in pieces
    /// keeps every character a plain character.
    private static let ligatures = ["ffi", "ffl", "ff", "fi", "fl", "ĳĳ"]

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

            let pieces = split(line.text).map { CTLineCreateWithAttributedString(
                CFAttributedStringCreate(nil, $0 as CFString, [kCTFontAttributeName: font] as CFDictionary)!
            ) }

            var total: CGFloat = 0
            for piece in pieces {
                var advance: CGFloat = 0
                CTLineGetTypographicBounds(piece, nil, nil, &advance)
                total += advance
            }

            var squeeze: CGFloat = 1
            if options.squeezeLines, total > 0 {
                let target = CGFloat(line.box.width) * width
                squeeze = min(max(target / total, 0.4), 2.5)
            }

            let originX = CGFloat(line.box.minX) * width
            let baselineY = (CGFloat(line.box.minY) + CGFloat(line.box.height) * 0.80) * height

            var cursor = originX
            for piece in pieces {
                var advance: CGFloat = 0
                CTLineGetTypographicBounds(piece, nil, nil, &advance)
                context.textMatrix = CGAffineTransform(a: squeeze, b: 0, c: 0, d: 1, tx: cursor, ty: baselineY)
                CTLineDraw(piece, context)
                cursor += advance * squeeze
            }
            stats.lines += 1
        }

        context.restoreGState()
        return stats
    }

    /// Breaks `text` at every ligature opportunity, so no piece can be folded.
    static func split(_ text: String) -> [String] {
        let characters = Array(text)
        var pieces: [String] = []
        var current = ""
        var index = 0

        while index < characters.count {
            var matched = ""
            for ligature in ligatures where matchesAt(characters, ligature, at: index) {
                if ligature.count > matched.count { matched = ligature }
            }
            if matched.isEmpty {
                current.append(characters[index])
                index += 1
            } else {
                if !current.isEmpty { pieces.append(current); current = "" }
                // One character per piece: a piece that still held "fi" would
                // just be folded again by CoreText.
                for character in matched { pieces.append(String(character)) }
                index += matched.count
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces.isEmpty ? [text] : pieces
    }

    private static func matchesAt(_ characters: [Character], _ ligature: String, at index: Int) -> Bool {
        let wanted = Array(ligature)
        guard index + wanted.count <= characters.count else { return false }
        for offset in wanted.indices where characters[index + offset] != wanted[offset] {
            return false
        }
        return true
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
