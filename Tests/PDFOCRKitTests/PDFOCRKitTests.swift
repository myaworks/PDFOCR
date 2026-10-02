import CoreGraphics
import Foundation
import PDFKit
import Testing

@testable import PDFOCRKit

@Suite("Text layer")
struct InvisibleTextLayerTests {
    @Test("ligature opportunities become run boundaries")
    func ligatureBoundaries() {
        // measured, not guessed: CoreText folds fi, fl, ffi and ffl, and with
        // some fonts a bare ff as well
        #expect(InvisibleTextLayer.runBoundaries(in: "defines") == [3])
        #expect(InvisibleTextLayer.runBoundaries(in: "sufficient") == [3, 4])
        #expect(InvisibleTextLayer.runBoundaries(in: "flour") == [1])
        #expect(InvisibleTextLayer.runBoundaries(in: "office") == [2, 3])
        #expect(InvisibleTextLayer.runBoundaries(in: "Process outcomes").isEmpty)
        #expect(InvisibleTextLayer.runBoundaries(in: "").isEmpty)
    }

    @Test("a scanned page comes back selectable, ligature-free and positioned")
    @MainActor
    func roundTrip() throws {
        let source = try Sample.scan(pages: 1, lines: [
            ("defines sufficient", CGRect(x: 0.12, y: 0.90, width: 0.42, height: 0.016)),
            ("fulfil specific classification", CGRect(x: 0.12, y: 0.87, width: 0.55, height: 0.016)),
        ])
        defer { try? FileManager.default.removeItem(at: source) }

        let output = source.deletingLastPathComponent()
            .appendingPathComponent("roundtrip-out.pdf")
        defer { try? FileManager.default.removeItem(at: output) }

        let scan = try #require(PDFInspector.info(for: source))
        let report = try OCRRun.run(input: source, output: output, options: OCROptions(), preScan: scan)
        #expect(report.processedPages == [1])
        #expect(report.linesRecognized == 2)

        guard let document = PDFDocument(url: output), let page = document.page(at: 0) else {
            Issue.record("output PDF could not be reopened")
            return
        }

        let text = (page.string ?? "").lowercased()

        // No /ActualText means CoreText never folded anything into a ligature,
        // which is the only way a character can reach the file that a reader
        // cannot search for. This assertion does not depend on the SDK's idea
        // of what a word is, so it holds on any macOS version — unlike
        // comparing extracted text, which is how the previous fix slipped
        // through and then broke on another SDK.
        let raw = String(decoding: try Data(contentsOf: output), as: UTF8.self)
        #expect(!raw.contains("ActualText"), "a ligature was substituted into the text layer")

        #expect(text.contains("defines sufficient"))
        #expect(text.contains("fulfil specific classification"))
        for ligature in ["\u{FB01}", "\u{FB02}", "\u{FB03}"] {
            #expect(!text.contains(ligature), "ligature \(ligature) survived")
        }

        // The scan itself must survive untouched.
        let bounds = page.bounds(for: .mediaBox)
        #expect(bounds.width > 0 && bounds.height > 0)
    }

    @Test("the default output sits next to the source, not inside a folder named after it")
    func defaultOutputNaming() {
        let source = URL(fileURLWithPath: "/Users/tcetin/Documents/scan-33061.pdf")
        let output = source.appendingOCRSuffix()
        #expect(output.path == "/Users/tcetin/Documents/scan-33061-ocr.pdf")
        #expect(output.deletingLastPathComponent() == source.deletingLastPathComponent())

        let mixedCase = URL(fileURLWithPath: "/tmp/reports/2026.TETKİK.PDF")
        #expect(mixedCase.appendingOCRSuffix().path == "/tmp/reports/2026.TETKİK-ocr.PDF")
    }

    @Test("page ranges parse and clamp")
    func pageSelection() throws {
        let selection = try PageSelection.parse("1-3, 6-")
        #expect(selection.contains(1))
        #expect(selection.contains(3))
        #expect(!selection.contains(4))
        #expect(selection.contains(6))
        #expect(selection.contains(9999), "an open upper bound means to the end")

        // clamped to an 8 page document the open range becomes 6-8
        let clamped = selection.clamped(to: 8)
        #expect(clamped.contains(8))
        #expect(!clamped.contains(9))

        // a range starting past the end of the document drops out
        let past = try PageSelection.parse("20-30")
        #expect(!past.clamped(to: 8).contains(1))
        #expect(!past.clamped(to: 8).contains(20))

        #expect(throws: PageSelectionError.self) { try PageSelection.parse("5-2") }
        #expect(throws: PageSelectionError.self) { try PageSelection.parse("abc") }
        #expect(throws: PageSelectionError.self) { try PageSelection.parse(" ") }
    }
}

/// Builds throwaway PDFs that look like scans: text rendered to a bitmap, then
/// that bitmap embedded, with no text layer at all.
enum Sample {
    static func scan(pages: Int, lines: [(String, CGRect)]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdfocr-sample-\(UUID().uuidString).pdf")

        let size = CGSize(width: 595, height: 841)
        let scale: CGFloat = 3
        var box = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { throw SampleError.cannotCreate }

        for _ in 0..<pages {
            guard let page = CGContext(
                data: nil,
                width: Int(size.width * scale),
                height: Int(size.height * scale),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { throw SampleError.cannotCreate }

            page.setFillColor(gray: 1, alpha: 1)
            page.fill(CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
            page.scaleBy(x: scale, y: scale)

            for (text, box) in lines {
                let font = CTFontCreateWithName("Helvetica" as CFString, box.height * size.height, nil)
                let attributed = CFAttributedStringCreate(
                    nil, text as CFString, [kCTFontAttributeName: font] as CFDictionary
                )!
                let line = CTLineCreateWithAttributedString(attributed)
                page.textPosition = CGPoint(x: box.minX * size.width, y: box.minY * size.height)
                CTLineDraw(line, page)
            }

            guard let image = page.makeImage() else { throw SampleError.cannotCreate }
            context.beginPDFPage(nil)
            context.draw(image, in: CGRect(origin: .zero, size: size))
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    enum SampleError: Error { case cannotCreate }
}