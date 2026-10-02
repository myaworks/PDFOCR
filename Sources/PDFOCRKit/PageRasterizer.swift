import CoreGraphics
import Foundation

/// A single recognized line, in Vision's coordinate convention: a normalized
/// rectangle whose origin is the bottom-left of the rasterized page.
public struct RecognizedLine: Sendable, Equatable {
    public let text: String
    public let box: CGRect
    public let confidence: Float

    public init(text: String, box: CGRect, confidence: Float) {
        self.text = text
        self.box = box
        self.confidence = confidence
    }
}

/// Page-space facts that both the rasterizer and the text layer need to agree on.
/// `/Rotate` is read once per page by the caller (PDFKit exposes it; CoreGraphics
/// does not) and threaded through here as a plain integer.
public enum PageGeometry {
    /// The size of the page as a reader shows it, i.e. with `/Rotate` applied.
    public static func displaySize(mediaBox: CGSize, rotation: Int) -> CGSize {
        switch rotation {
        case 90, 270: CGSize(width: mediaBox.height, height: mediaBox.width)
        default: mediaBox
        }
    }

    /// Maps display space (what Vision saw) back to unrotated PDF page space.
    /// Applying it to the text matrix makes glyphs land exactly on their ink
    /// while still reading left-to-right on screen.
    public static func displayToPageTransform(mediaBox: CGRect, rotation: Int) -> CGAffineTransform {
        let w = mediaBox.width
        let h = mediaBox.height
        switch rotation {
        case 90:
            return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: h)
        case 180:
            return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h)
        case 270:
            return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: w, ty: 0)
        default:
            return .identity
        }
    }
}

/// Renders a PDF page to a bitmap the way a reader displays it.
public enum PageRasterizer {
    public static func image(
        for page: CGPDFPage,
        rotation: Int,
        dpi: Double,
        maxPixels: Int
    ) -> CGImage? {
        let box = page.getBoxRect(.mediaBox)
        guard box.width > 0, box.height > 0, dpi > 0 else { return nil }

        let display = PageGeometry.displaySize(mediaBox: box.size, rotation: rotation)

        var scale = CGFloat(dpi / 72.0)
        let area = display.width * display.height
        if area > 0 {
            let cap = CGFloat(maxPixels).squareRoot() / area.squareRoot()
            if scale > cap { scale = cap }
        }

        let width = Int((display.width * scale).rounded())
        let height = Int((display.height * scale).rounded())
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return nil }

        // Scans are frequently black-on-transparent or JPEG-black; an opaque
        // white ground is what Vision expects.
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        switch rotation {
        case 90:
            ctx.rotate(by: .pi / 2)
            ctx.translateBy(x: box.height, y: 0)
        case 180:
            ctx.rotate(by: .pi)
            ctx.translateBy(x: box.width, y: box.height)
        case 270:
            ctx.rotate(by: -.pi / 2)
            ctx.translateBy(x: 0, y: box.width)
        default:
            break
        }
        ctx.drawPDFPage(page)

        return ctx.makeImage()
    }
}
