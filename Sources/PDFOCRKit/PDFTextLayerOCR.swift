import CoreGraphics
import Foundation

public enum OCRError: Error, CustomStringConvertible {
    case cannotOpenPDF(URL)
    case noPages(URL)
    case cannotCreateOutput(URL)
    case cannotCreateContext
    case cancelled

    public var description: String {
        switch self {
        case .cannotOpenPDF(let url): "cannot open '\(url.lastPathComponent)' as a PDF"
        case .noPages(let url): "'\(url.lastPathComponent)' has no pages"
        case .cannotCreateOutput(let url): "cannot write '\(url.lastPathComponent)'"
        case .cannotCreateContext: "cannot create a PDF context"
        case .cancelled: "cancelled"
        }
    }
}

public struct OCRReport: Sendable {
    public var input: URL
    public var output: URL
    public var totalPages = 0
    public var processedPages: [Int] = []
    public var skippedPages: [Int] = []
    public var replacedPages: [Int] = []
    public var emptyPages: [Int] = []
    public var linesRecognized = 0
    /// Characters the chosen font has no glyph for; they cannot be read back.
    public var unmappedCharacters = 0
    public var averageConfidence: Float = 0
    public var duration: TimeInterval = 0
    public var cancelled = false
    /// Non-fatal things worth telling the user about.
    public var warnings: [String] = []

    var confidenceTotal: Float = 0
    var confidenceSamples: Int = 0
}

public struct OCRProgress: Sendable {
    public let page: Int
    public let total: Int
    public var fraction: Double { total > 0 ? Double(page) / Double(total) : 0 }
}

public enum OCRRun {
    /// Adds a searchable text layer to the selected pages of `input`.
    ///
    /// Each page is replayed into a fresh page and the recognized text is drawn
    /// on top in invisible render mode, so the scan is untouched. Bookmarks,
    /// form fields and link annotations of the source are not carried over.
    @discardableResult
    public static func run(
        input: URL,
        output: URL,
        options: OCROptions = OCROptions(),
        preScan: DocumentInfo,
        progress: @Sendable (OCRProgress) -> Void = { _ in },
        shouldCancel: @Sendable () -> Bool = { false }
    ) throws -> OCRReport {
        let started = Date()
        var report = OCRReport(input: input, output: output)

        guard let document = CGPDFDocument(input as CFURL) else {
            throw OCRError.cannotOpenPDF(input)
        }
        let pageCount = document.numberOfPages
        report.totalPages = pageCount
        guard pageCount > 0 else { throw OCRError.noPages(input) }

        // The caller reads the page facts with PDFKit on the main thread and
        // passes them in; everything below is pure CoreGraphics and safe on
        // any thread.
        let selection = options.pageSelection.clamped(to: pageCount)
        // Asking for a replacement implies "process these pages too".
        let skipUntouched = options.skipPagesWithText && !options.replaceExistingText
        let existingText = (skipUntouched || options.replaceExistingText) ? preScan.pagesWithText : []
        let rotations = preScan.rotations

        try? FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard let consumer = CGDataConsumer(url: output as CFURL) else {
            throw OCRError.cannotCreateOutput(output)
        }
        let firstBox = document.page(at: 1)?.getBoxRect(.mediaBox)
            ?? CGRect(x: 0, y: 0, width: 595, height: 842)
        var initialBox = firstBox
        guard let context = CGContext(consumer: consumer, mediaBox: &initialBox, nil) else {
            throw OCRError.cannotCreateContext
        }

        var textDump: [String] = []

        for index in 1...pageCount {
            if shouldCancel() { break }
            guard let page = document.page(at: index) else { continue }

            let mediaBox = page.getBoxRect(.mediaBox)
            let rotation = rotations[index] ?? 0
            let display = PageGeometry.displaySize(mediaBox: mediaBox.size, rotation: rotation)

            let selected = selection.contains(index)
            let hadText = existingText.contains(index)
            let process = selected && (!hadText || options.replaceExistingText)

            var box = mediaBox
            let pageInfo = [
                kCGPDFContextMediaBox as String: Data(bytes: &box, count: MemoryLayout<CGRect>.size)
            ]
            context.beginPDFPage(pageInfo as CFDictionary)

            // A page's old text layer lives in its content stream, so replacing
            // the text means the page has to be laid down as a bitmap instead.
            var bitmap: CGImage?
            if process, hadText, options.replaceExistingText {
                bitmap = PageRasterizer.image(
                    for: page, rotation: rotation, dpi: options.dpi, maxPixels: options.maxRasterPixels
                )
                if let bitmap {
                    context.saveGState()
                    context.concatenate(
                        PageGeometry.displayToPageTransform(mediaBox: mediaBox, rotation: rotation)
                    )
                    context.draw(bitmap, in: CGRect(origin: .zero, size: display))
                    context.restoreGState()
                    report.replacedPages.append(index)
                }
            }
            if bitmap == nil {
                context.saveGState()
                context.translateBy(x: -mediaBox.minX, y: -mediaBox.minY)
                context.drawPDFPage(page)
                context.restoreGState()
            }

            if process {
                if bitmap == nil {
                    bitmap = PageRasterizer.image(
                        for: page, rotation: rotation, dpi: options.dpi, maxPixels: options.maxRasterPixels
                    )
                }
                if let bitmap, let lines = try? TextRecognizer.recognize(image: bitmap, options: options) {
                    let stats = InvisibleTextLayer.draw(
                        lines: lines,
                        displaySize: display,
                        mediaBox: mediaBox,
                        rotation: rotation,
                        options: options,
                        in: context
                    )
                    report.processedPages.append(index)
                    report.linesRecognized += stats.lines
                    report.unmappedCharacters += stats.unmappedCharacters
                    if lines.isEmpty {
                        report.emptyPages.append(index)
                    } else {
                        report.confidenceTotal += lines.reduce(Float.zero) { $0 + $1.confidence }
                        report.confidenceSamples += lines.count
                    }
                    if options.writePlainText {
                        textDump.append("--- page \(index) ---")
                        textDump.append(contentsOf: lines.map(\.text))
                    }
                } else {
                    report.warnings.append("page \(index) could not be read")
                }
            } else if selected, hadText {
                report.skippedPages.append(index)
            }

            context.endPDFPage()
            progress(OCRProgress(page: index, total: pageCount))
        }

        context.closePDF()
        report.cancelled = shouldCancel()
        report.averageConfidence = report.confidenceSamples > 0
            ? report.confidenceTotal / Float(report.confidenceSamples)
            : 0
        report.duration = Date().timeIntervalSince(started)

        if report.processedPages.isEmpty {
            report.warnings.append("no pages were processed")
        }
        if !report.emptyPages.isEmpty {
            report.warnings.append(
                "\(report.emptyPages.count) page(s) had no recognizable text: \(summarize(report.emptyPages))"
            )
        }
        if report.unmappedCharacters > 0 {
            report.warnings.append(
                "\(report.unmappedCharacters) character(s) have no glyph in the chosen font and "
                + "cannot be read back; try --font unicode"
            )
        }
        if !report.replacedPages.isEmpty {
            report.warnings.append(
                "\(report.replacedPages.count) existing text layer(s) replaced; "
                + "those pages were re-laid as bitmaps"
            )
        }

        if options.writePlainText {
            let textURL = output.deletingPathExtension().appendingPathExtension("txt")
            try? textDump.joined(separator: "\n").write(to: textURL, atomically: true, encoding: .utf8)
        }

        return report
    }

    private static func summarize(_ pages: [Int]) -> String {
        let head = pages.prefix(10).map(String.init).joined(separator: ", ")
        return pages.count > 10 ? "\(head), …" : head
    }
}
