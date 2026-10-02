import PDFOCRKit
import SwiftUI

struct QueueView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.items.isEmpty {
                ContentUnavailableView {
                    Label("PDF ekle", systemImage: "doc.viewfinder")
                } description: {
                    Text("Taranmış PDF'leri sürükleyip bırak ya da sol üstteki + düğmesini kullan. "
                        + "Metin katmanı eklenir; görsel olduğu gibi kalır.")
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.items) { item in
                            JobCard(item: item, model: model)
                        }
                    }
                    .frame(maxWidth: 780)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            StatusBar(model: model)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct JobCard: View {
    let item: AppModel.Item
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.url.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let info = item.info {
                        Text("\(info.pageCount) sayfa · \(info.pagesWithoutText) sayfada metin yok")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                statusControl
            }

            if item.phase == .running {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
            }

            if let output = item.output, item.phase.isFinished {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(.tint)
                    Text(output.lastPathComponent)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Aç") {
                        NSWorkspace.shared.open(output)
                    }
                    .controlSize(.small)
                    Button("Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([output])
                    }
                    .controlSize(.small)
                }
            }

            ForEach(findings, id: \.self) { finding in
                Label(finding, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if case .failed(let message) = item.phase {
                Label(message, systemImage: "xmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    /// The findings in Turkish, built from the report rather than from the
    /// library's own English strings.
    private var findings: [String] {
        guard let report = item.report else { return [] }
        var messages: [String] = []
        if !report.emptyPages.isEmpty {
            messages.append("\(report.emptyPages.count) sayfada okunabilir metin bulunamadı: \(list(report.emptyPages))")
        }
        if !report.replacedPages.isEmpty {
            messages.append("\(report.replacedPages.count) eski metin katmanı temizlendi; bu sayfalar bitmap olarak yeniden yazıldı")
        }
        if report.unmappedCharacters > 0 {
            messages.append("\(report.unmappedCharacters) karakter seçili fontta karşılığı yok, okunmayacak — Unicode fontu dene")
        }
        return messages
    }

    private func list(_ pages: [Int]) -> String {
        pages.count <= 10 ? pages.map(String.init).joined(separator: ", ")
            : pages.prefix(10).map(String.init).joined(separator: ", ") + "…"
    }

    private var fraction: Double {
        guard let info = item.info, info.pageCount > 0 else { return 0 }
        return min(1, Double(item.page) / Double(info.pageCount))
    }

    @ViewBuilder
    private var statusControl: some View {
        switch item.phase {
        case .waiting:
            if let suggested = model.suggestedMode(for: item) {
                Button {
                    model.mode = suggested
                } label: {
                    Label(suggested.title, systemImage: suggested.symbol)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("Bu dosya için önerilen: \(suggested.explanation)")
            }
        case .running:
            ProgressView()
                .controlSize(.small)
        case .done:
            Label(
                "\(item.lines) satır · \(String(format: "%.1fs", item.duration))",
                systemImage: "checkmark.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(.green)
        case .cancelled:
            Label("Durduruldu", systemImage: "pause.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed:
            Text("Hata")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}

private struct StatusBar: View {
    @Bindable var model: AppModel

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 14) {
                if model.isRunning, let active = model.items.first(where: { $0.id == model.activeItemID }) {
                    ProgressView()
                        .controlSize(.small)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(active.url.lastPathComponent)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        ProgressView(value: fraction(for: active))
                            .progressViewStyle(.linear)
                            .frame(width: 180)
                    }
                } else {
                    Label(statusText, systemImage: model.isRunning ? "gearshape.2" : "checkmark.seal")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if model.isRunning {
                    Button(role: .cancel) {
                        model.cancel()
                    } label: {
                        Label("Durdur", systemImage: "stop.fill")
                    }
                    .buttonStyle(.glass)
                } else {
                    Button {
                        model.start()
                    } label: {
                        Label("Başlat", systemImage: "play.fill")
                    }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.items.allSatisfy { $0.phase.isFinished || $0.isUnreadable })
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
            .padding(10)
        }
    }

    private var statusText: String {
        if model.items.isEmpty { return "Hazır" }
        let pending = model.items.count - model.finishedCount
        if pending == 0 {
            return "\(model.finishedCount) dosya tamam · \(model.totalPages) sayfa"
        }
        return "\(model.items.count) dosya · \(model.totalPages) sayfa · \(pending) sırada"
    }

    private func fraction(for item: AppModel.Item) -> Double {
        guard let info = item.info, info.pageCount > 0 else { return 0 }
        return min(1, Double(item.page) / Double(info.pageCount))
    }
}