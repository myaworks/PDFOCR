import Foundation
import PDFOCRKit
import SwiftUI

/// How a file should be treated.
enum ProcessingMode: String, CaseIterable, Identifiable, Codable {
    case fillGaps
    case redo
    case replace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fillGaps: "Eksikleri tamamla"
        case .redo: "Hepsini yeniden OCR et"
        case .replace: "Eski katmanı temizle"
        }
    }

    var symbol: String {
        switch self {
        case .fillGaps: "circle.dotted"
        case .redo: "arrow.clockwise"
        case .replace: "eraser"
        }
    }

    var explanation: String {
        switch self {
        case .fillGaps:
            "Metni olmayan sayfalara katman ekler, olanlara dokunmaz. En güvenli seçenek."
        case .redo:
            "Bütün sayfaları yeniden okur. Sayfadaki mevcut katman korunur, aramalarda ikisi de çıkar."
        case .replace:
            "Bütün sayfaları yeniden okur ve eski katmanı siler. Sayfayı bitmap'e çevirdiği için "
                + "vurgular ve vektör içerik kaybolur, dosya büyür."
        }
    }

    var options: OCROptions {
        var options = OCROptions()
        switch self {
        case .fillGaps:
            options.skipPagesWithText = true
            options.replaceExistingText = false
        case .redo:
            options.skipPagesWithText = false
            options.replaceExistingText = false
        case .replace:
            options.skipPagesWithText = false
            options.replaceExistingText = true
        }
        return options
    }

    /// The mode that makes sense for a file, given what is already in it.
    static func suggested(for info: DocumentInfo) -> ProcessingMode {
        if info.hasNoTextAtAll { return .fillGaps }
        if info.isFullySearchable { return .redo }
        if info.suspiciousPages * 3 > info.withTextCount { return .replace }
        return .fillGaps
    }
}

enum OutputDestination: String, CaseIterable, Identifiable, Codable {
    case besideSource
    case chosenFolder

    var id: String { rawValue }
    var title: String { self == .besideSource ? "Kaynağın yanına" : "Kendi klasörüme" }
}

struct Preset: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var options: OCROptions
    var mode: ProcessingMode = .fillGaps
    var destination: OutputDestination = .besideSource
    var customFolder: URL?
}

/// A named set of settings the user can come back to.
@Observable
final class PresetStore {
    private static let key = "pdfocr.presets"

    private(set) var presets: [Preset] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key) {
            presets = (try? JSONDecoder().decode([Preset].self, from: data)) ?? []
        }
        if presets.isEmpty { presets = PresetStore.starterPresets }
    }

    private static let starterPresets: [Preset] = [
        Preset(name: "Standart", options: OCROptions(), mode: .fillGaps),
        Preset(
            name: "Tablo yoğun",
            options: {
                var options = OCROptions()
                options.dpi = 400
                options.recognitionLevel = .accurate
                options.squeezeLines = true
                return options
            }(),
            mode: .fillGaps
        ),
        Preset(
            name: "Çok dilli",
            options: {
                var options = OCROptions()
                options.languages = ["en-US", "tr-TR", "de-DE", "fr-FR"]
                return options
            }(),
            mode: .fillGaps
        ),
    ]

    func save(_ preset: Preset) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        } else {
            presets.append(preset)
        }
        persist()
    }

    func remove(at offsets: IndexSet) {
        presets.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        let data = try? JSONEncoder().encode(presets)
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}

extension Array {
    mutating func remove(atOffsets offsets: IndexSet) {
        for index in offsets.sorted(by: >) where indices.contains(index) {
            remove(at: index)
        }
    }
}