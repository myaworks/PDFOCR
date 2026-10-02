import Foundation

public enum PageSelectionError: Error, CustomStringConvertible {
    case emptySpec
    case badToken(String)
    case reversedRange(String)

    public var description: String {
        switch self {
        case .emptySpec: "page range is empty"
        case .badToken(let t): "cannot read page range token '\(t)'"
        case .reversedRange(let t): "page range '\(t)' ends before it starts"
        }
    }
}

/// Which 1-based pages to process. Accepts `1-10, 15, 20-`; an open upper bound is
/// stored as `Int.max` and clamped against the real page count when used.
public enum PageSelection: Sendable, Equatable {
    case all
    case ranges([ClosedRange<Int>])

    public static let openEnded = Int.max

    public static func parse(_ spec: String) throws -> PageSelection {
        var ranges: [ClosedRange<Int>] = []

        for raw in spec.split(separator: ",") {
            let token = raw.trimmingCharacters(in: .whitespaces)
            guard !token.isEmpty else { continue }

            let lower: Int
            let upper: Int
            if let dash = token.firstIndex(of: "-") {
                let lowText = token[token.startIndex..<dash].trimmingCharacters(in: .whitespaces)
                let highText = token[token.index(after: dash)...].trimmingCharacters(in: .whitespaces)

                if lowText.isEmpty && highText.isEmpty { throw PageSelectionError.badToken(token) }
                if lowText.isEmpty {
                    lower = 1
                } else if let value = Int(lowText) {
                    lower = value
                } else {
                    throw PageSelectionError.badToken(token)
                }
                if highText.isEmpty {
                    upper = openEnded
                } else if let value = Int(highText) {
                    upper = value
                } else {
                    throw PageSelectionError.badToken(token)
                }
            } else {
                guard let page = Int(token) else { throw PageSelectionError.badToken(token) }
                lower = page
                upper = page
            }

            guard lower >= 1, upper >= lower else { throw PageSelectionError.reversedRange(token) }
            ranges.append(lower...upper)
        }

        guard !ranges.isEmpty else { throw PageSelectionError.emptySpec }
        return .ranges(ranges)
    }

    public func contains(_ oneBasedPage: Int) -> Bool {
        switch self {
        case .all:
            true
        case .ranges(let ranges):
            ranges.contains { $0.contains(oneBasedPage) }
        }
    }

    public var isAll: Bool { self == .all }

    public func clamped(to pageCount: Int) -> PageSelection {
        guard case .ranges(let ranges) = self else { return self }
        let kept = ranges.compactMap { r -> ClosedRange<Int>? in
            let lo = max(1, r.lowerBound)
            let hi = min(pageCount, r.upperBound)
            return lo <= hi ? lo...hi : nil
        }
        return .ranges(kept)
    }
}
