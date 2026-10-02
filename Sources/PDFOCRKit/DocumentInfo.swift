import Foundation
import PDFKit

/// What is already inside a PDF, so the UI can tell a fresh scan from a
/// partially OCR'd one before spending any time on it.
///
/// It also carries the two page facts the pipeline needs: which pages already
/// have text, and which are `/Rotate`d. Reading them means opening the file with
/// PDFKit, which has to happen on the main thread — so this is read once up
/// front and handed to the OCR work, which then runs anywhere.
public struct DocumentInfo: Sendable {
    public let url: URL
    public let pageCount: Int
    /// 1-based page numbers that already carry extractable text.
    public let pagesWithText: Set<Int>
    /// Pages whose existing text layer is too short to be real body text.
    public let suspiciousPages: Int
    /// 1-based page number to `/Rotate` angle, normalized to 0/90/180/270.
    public let rotations: [Int: Int]

    public init(
        url: URL,
        pageCount: Int,
        pagesWithText: Set<Int>,
        suspiciousPages: Int,
        rotations: [Int: Int]
    ) {
        self.url = url
        self.pageCount = pageCount
        self.pagesWithText = pagesWithText
        self.suspiciousPages = suspiciousPages
        self.rotations = rotations
    }

    public var withTextCount: Int { pagesWithText.count }
    public var pagesWithoutText: Int { max(0, pageCount - pagesWithText.count) }
    public var hasNoTextAtAll: Bool { pageCount > 0 && pagesWithText.isEmpty }
    public var isFullySearchable: Bool { pageCount > 0 && pagesWithText.count == pageCount }

    public var textCoverage: Double {
        pageCount > 0 ? Double(pagesWithText.count) / Double(pageCount) : 0
    }

    public var status: Coverage {
        if pageCount == 0 { return .unreadable }
        if isFullySearchable { return .complete }
        if hasNoTextAtAll { return .none }
        return .partial(pagesWithText.count)
    }

    public enum Coverage: Equatable, Sendable {
        case unreadable
        case none
        case complete
        case partial(Int)
    }
}

public enum PDFInspector {
    /// Cheap enough to run on every file the moment it is added.
    ///
    /// - Important: must be called on the main thread.
    @MainActor
    public static func info(for url: URL) -> DocumentInfo? {
        guard let document = PDFDocument(url: url) else { return nil }

        var withText = Set<Int>()
        var suspicious = 0
        var rotations: [Int: Int] = [:]

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let number = index + 1

            let angle = page.rotation
            if angle != 0 { rotations[number] = ((angle % 360) + 360) % 360 }

            guard let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else { continue }
            withText.insert(number)
            // A real body page carries far more than a stray header or footer.
            if text.count < 120 { suspicious += 1 }
        }

        return DocumentInfo(
            url: url,
            pageCount: document.pageCount,
            pagesWithText: withText,
            suspiciousPages: suspicious,
            rotations: rotations
        )
    }

    /// Languages worth putting in front of a person, first.
    public static let commonLanguages = [
        "en-US", "tr-TR", "de-DE", "fr-FR", "es-ES", "it-IT",
        "pt-PT", "nl-NL", "pl-PL", "ru-RU", "ar-SA", "zh-Hans",
        "ja-JP", "ko-KR",
    ]
}