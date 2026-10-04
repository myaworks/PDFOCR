import Foundation
import PDFOCRKit
import SwiftUI

@MainActor
@Observable
final class AppModel {
    struct Item: Identifiable {
        let id = UUID()
        var url: URL
        var info: DocumentInfo?
        var phase: Phase = .waiting
        var page = 0
        var lines = 0
        var duration: TimeInterval = 0
        var output: URL?
        var failure: String?
        /// Kept whole so the UI can word the findings itself.
        var report: OCRReport?

        var isUnreadable: Bool { info?.status == .unreadable }
    }

    enum Phase: Equatable {
        case waiting
        case running
        case done
        case cancelled
        case failed(String)

        var isFinished: Bool {
            switch self {
            case .done, .cancelled, .failed: true
            case .waiting, .running: false
            }
        }
    }

    // settings
    var mode: ProcessingMode = .fillGaps
    var destination: OutputDestination = .besideSource
    var outputFolder: URL?
    var languages: [String] = OCROptions().languages
    var dpi: Double = OCROptions().dpi
    var recognitionLevel: RecognitionLevel = .accurate
    var baseFont: BaseFont = .helvetica
    var fontSizeMode: FontSizeMode = .matchBox
    var fixedFontSize: Double = 9
    var squeezeLines = true
    var skipPagesWithText = true
    var pageRangeText = ""
    var minimumConfidence: Double = 0
    var writePlainText = false
    var advanced = false

    var presetStore = PresetStore()
    var items: [Item] = []
    var isRunning = false
    var activeItemID: Item.ID?
    var isChoosingFiles = false

    var totalPages: Int { items.reduce(0) { $0 + ($1.info?.pageCount ?? 0) } }
    var finishedCount: Int { items.filter { $0.phase.isFinished }.count }

    var effectiveOptions: OCROptions {
        var options = mode.options
        options.languages = languages
        options.dpi = dpi
        options.recognitionLevel = recognitionLevel
        options.baseFont = baseFont
        options.fontSizeMode = fontSizeMode == .matchBox ? .matchBox : FontSizeMode.fixed(fixedFontSize)
        options.squeezeLines = squeezeLines
        options.skipPagesWithText = skipPagesWithText && mode == .fillGaps
        options.minimumConfidence = Float(minimumConfidence)
        options.writePlainText = writePlainText
        let trimmed = pageRangeText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            options.pageSelection = (try? PageSelection.parse(trimmed)) ?? .all
        }
        return options
    }

    // MARK: - queue

    func add(urls: [URL]) {
        let existing = Set(items.map(\.url.standardizedFileURL))
        for url in urls where !existing.contains(url.standardizedFileURL) {
            var item = Item(url: url)
            item.info = PDFInspector.info(for: url)
            if item.info == nil {
                item.phase = .failed("PDF açılamadı — parola korumalı olabilir")
            }
            items.append(item)
        }
        suggestMode()
    }

    func remove(_ item: Item) {
        guard !isRunning else { return }
        items.removeAll { $0.id == item.id }
    }

    func removeFinished() {
        guard !isRunning else { return }
        items.removeAll { $0.phase.isFinished }
    }

    func clearAll() {
        guard !isRunning else { return }
        items.removeAll()
    }

    /// Picks the mode that fits the least-processed file in the list.
    private func suggestMode() {
        let candidates = items.compactMap(\.info).filter { !$0.hasNoTextAtAll }
        if let worst = candidates.min(by: { $0.textCoverage < $1.textCoverage }) {
            mode = ProcessingMode.suggested(for: worst)
        }
    }

    func suggestedMode(for item: Item) -> ProcessingMode? {
        item.info.map(ProcessingMode.suggested(for:))
    }

    func destination(for item: Item) -> URL {
        outputDestination(for: item, folder: outputFolder)
    }

    // MARK: - run

    func start() {
        guard !isRunning else { return }
        let queue = items.filter { !$0.phase.isFinished && !$0.isUnreadable }
        guard !queue.isEmpty else { return }

        let options = effectiveOptions
        let overwrite = destination
        let folder = outputFolder
        isRunning = true
        // Only reset what is about to run; a finished file must keep its
        // result when a later batch starts.
        let queueIDs = queue.map(\.id)
        for index in items.indices where queueIDs.contains(items[index].id) {
            items[index].phase = .waiting
        }

        Task { [weak self] in
            guard let self else { return }
            for id in queue.map(\.id) {
                if Task.isCancelled { break }

                guard let position = self.items.firstIndex(where: { $0.id == id }) else { continue }
                let item = self.items[position]
                let input = item.url
                guard let scan = item.info else { continue }
                let target = self.outputDestination(for: item, folder: folder)
                let isFolder = overwrite == .chosenFolder
                if !isFolder, FileManager.default.fileExists(atPath: target.path) {
                    try? FileManager.default.removeItem(at: target)
                }

                self.items[position].phase = .running
                self.activeItemID = id

                do {
                    let report = try await Task.detached(priority: .userInitiated) {
                        try OCRRun.run(
                            input: input,
                            output: target,
                            options: options,
                            preScan: scan,
                            // The OCR runs off the main actor, so progress
                            // hops back through the main queue. AppModel is
                            // main-actor isolated, which makes it Sendable, so
                            // capturing it here is fine.
                            progress: { progress in
                                DispatchQueue.main.async {
                                    self.update(id: id, page: progress.page)
                                }
                            },
                            shouldCancel: { Task.isCancelled }
                        )
                    }.value

                    self.items[position].output = target
                    self.items[position].lines = report.linesRecognized
                    self.items[position].duration = report.duration
                    self.items[position].report = report
                    self.items[position].phase = report.cancelled ? .cancelled : .done
                } catch is CancellationError {
                    self.items[position].phase = .cancelled
                } catch {
                    self.items[position].phase = .failed(error.localizedDescription)
                }
            }
            self.activeItemID = nil
            self.isRunning = false
        }
    }

    func cancel() {
        guard isRunning else { return }
        for index in items.indices where items[index].phase == .running {
            items[index].phase = .cancelled
        }
        isRunning = false
    }

    private func update(id: Item.ID, page: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard items[index].page != page else { return }
        items[index].page = page
    }

    private func outputDestination(for item: Item, folder: URL?) -> URL {
        guard destination == .chosenFolder, let folder else {
            return item.url.appendingOCRSuffix()
        }
        return folder.appendingPathComponent(
            item.url.deletingPathExtension().lastPathComponent + "-ocr.pdf"
        )
    }

    // MARK: - presets

    func currentPreset(named name: String) {
        guard let preset = presetStore.presets.first(where: { $0.name == name }) else { return }
        apply(preset)
    }

    func savePreset(named name: String) {
        var preset = Preset(
            name: name,
            options: effectiveOptions,
            mode: mode,
            destination: destination,
            customFolder: outputFolder
        )
        preset.options.pageSelection = .all
        presetStore.save(preset)
    }

    private func apply(_ preset: Preset) {
        let options = preset.options
        mode = preset.mode
        destination = preset.destination
        outputFolder = preset.customFolder
        languages = options.languages
        dpi = options.dpi
        recognitionLevel = options.recognitionLevel
        baseFont = options.baseFont
        if case .fixed(let value) = options.fontSizeMode {
            fontSizeMode = FontSizeMode.fixed(value)
            fixedFontSize = value
        } else {
            fontSizeMode = .matchBox
        }
        squeezeLines = options.squeezeLines
        skipPagesWithText = options.skipPagesWithText
        minimumConfidence = Double(options.minimumConfidence)
        writePlainText = options.writePlainText
    }
}
